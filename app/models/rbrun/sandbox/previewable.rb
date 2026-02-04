# frozen_string_literal: true

module Rbrun
  class Sandbox
    # Handles Cloudflare Tunnel setup for secure preview URLs.
    #
    # All resources managed by deterministic name (sandbox-{id}).
    # No provider IDs stored - resources looked up by name when needed.
    #
    module Previewable
      extend ActiveSupport::Concern

      # Check if tunnel exists in Cloudflare.
      def tunnel_exists?
        cloudflare_client.find_tunnel(Naming.resource(slug)).present?
      end

      # Setup the Cloudflare tunnel for Docker Compose mode.
      def setup_compose_tunnel!
        return unless Rbrun.configuration.cloudflare_configured?

        cloudflare_client.ensure_sandbox_iframe_rule(cloudflare_zone_id)

        return if tunnel_healthy?

        hostname = Naming.hostname(slug, preview_zone)

        tunnel = cloudflare_client.find_or_create_tunnel(Naming.resource(slug))
        token = cloudflare_client.get_tunnel_token(tunnel[:id])

        ingress_rules = [
          { hostname:, service: "http://localhost:3000" },
          { service: "http_status:404" }
        ]
        cloudflare_client.configure_tunnel_ingress(tunnel[:id], ingress_rules)

        cloudflare_client.ensure_dns_record(cloudflare_zone_id, hostname, tunnel[:id])

        # Deploy widget injection worker
        deploy_sandbox_worker!

        start_compose_tunnel_container!(token)

        Rails.logger.info "[Rbrun::Sandbox] Compose tunnel + worker setup: #{hostname}"
      end

      # Delete the Cloudflare tunnel by name.
      def delete_compose_tunnel!
        stop_tunnel_container!

        # Delete worker
        begin
          cloudflare_client.delete_worker(slug)
        rescue Rbrun::HttpErrors::ApiError
          # Already deleted or never existed
        end

        tunnel = cloudflare_client.find_tunnel(Naming.resource(slug))
        return unless tunnel

        hostname = Naming.hostname(slug, preview_zone)
        begin
          record = cloudflare_client.find_dns_record(cloudflare_zone_id, hostname)
          cloudflare_client.delete_dns_record(cloudflare_zone_id, record["id"]) if record
        rescue Rbrun::HttpErrors::ApiError
          # Already deleted
        end

        begin
          cloudflare_client.delete_tunnel(tunnel[:id])
        rescue Rbrun::HttpErrors::ApiError
          # Already deleted
        end

        Rails.logger.info "[Rbrun::Sandbox] Compose tunnel deleted: #{Naming.resource(slug)}"
      end

      # Check if the tunnel is healthy.
      def tunnel_healthy?
        return false unless server_exists?

        tunnel = cloudflare_client.find_tunnel(Naming.resource(slug))
        return false unless tunnel

        exec = run_ssh!("docker ps -q -f name=#{Naming.container(slug, 'tunnel')}", raise_on_error: false, timeout: 10)
        return false if exec.output.blank?

        tunnel_status = cloudflare_client.get_tunnel(tunnel[:id])
        tunnel_status && tunnel_status[:status] != "inactive"
      end

      private

        def preview_zone
          Rbrun.configuration.cloudflare_config.domain
        end

        def cloudflare_client
          @cloudflare_client ||= Rbrun.configuration.cloudflare_config.client
        end

        def cloudflare_zone_id
          @cloudflare_zone_id ||= begin
            zone = cloudflare_client.find_zone(preview_zone)
            raise "Could not find Cloudflare zone for #{preview_zone}" unless zone
            zone["id"]
          end
        end

        def start_compose_tunnel_container!(token)
          name = Naming.container(slug, "tunnel")

          run_ssh!("docker rm -f #{name}", raise_on_error: false, timeout: 30)

          cmd = <<~CMD.squish
            docker run -d
              --name #{name}
              --network host
              --restart unless-stopped
              cloudflare/cloudflared:latest
              tunnel run --token #{Shellwords.escape(token)}
          CMD

          run_ssh!(cmd, timeout: 60)

          command_executions.create!(
            kind: "process",
            tag: "tunnel",
            command: "cloudflared tunnel run",
            image: "cloudflare/cloudflared:latest",
            container_id: name,
            started_at: Time.current
          )
        end

        def stop_tunnel_container!
          return unless server_exists?

          name = Naming.container(slug, "tunnel")
          run_ssh!("docker stop #{name}", raise_on_error: false, timeout: 30)
          run_ssh!("docker rm #{name}", raise_on_error: false, timeout: 30)
        rescue Ssh::Client::Error
          # Server might be down
        end

        def deploy_sandbox_worker!
          cloudflare_client.deploy_worker(slug, access_token:)
          cloudflare_client.create_worker_route(cloudflare_zone_id, slug, preview_zone)
          Rails.logger.info "[Rbrun::Sandbox] Worker deployed: #{Naming.worker(slug)}"
        end
    end
  end
end
