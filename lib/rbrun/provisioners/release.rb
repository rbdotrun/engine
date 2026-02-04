# frozen_string_literal: true

module Rbrun
  module Provisioners
    # K3s-based production deployment provisioner.
    class Release
      WORKSPACE = "/home/deploy/workspace"
      VOLUME_MOUNT_BASE = "/mnt/data"
      HTTP_NODE_PORT = 30080

      attr_reader :release

      def initialize(release)
        @release = release
      end

      def provision!
        return if release.deployed?

        create_infrastructure!
        install_k3s!
        provision_volumes! if needs_volumes?
        setup_tunnel! if cloudflare_configured?
        build_and_push_image! if config.app?
        deploy_kubernetes!
        wait_for_rollout!
      end

      def deprovision!
        cleanup_kubernetes! if server_exists?
        cleanup_tunnel! if cloudflare_configured?
        cleanup_volumes!
        delete_infrastructure!
      end

      def redeploy!
        raise "Release not deployed" unless release.deployed?

        build_and_push_image! if config.app?
        wait_for_rollout!
      end

      def server_exists?
        compute_client.find_server(prefix).present?
      end

      def repo_sync_command(workspace_exists:)
        clone_url = "https://#{config.git_config.pat}@github.com/#{config.git_config.repo}.git"
        branch = release.branch

        if workspace_exists
          ["pull", "cd #{WORKSPACE} && git fetch origin && git checkout #{branch} && git pull origin #{branch}"]
        else
          ["clone", "git clone --branch #{branch} #{Shellwords.escape(clone_url)} #{WORKSPACE}"]
        end
      end

      private

        def config
          @config ||= Rbrun.configuration
        end

        def prefix
          @prefix ||= Naming.release_prefix(config.git_config.app_name, release.environment)
        end

        def target
          release.environment.to_sym
        end

        def zone
          config.cloudflare_config&.domain
        end

        def cloudflare_configured?
          config.cloudflare_configured?
        end

        # ─────────────────────────────────────────────────────────────
        # Infrastructure
        # ─────────────────────────────────────────────────────────────

        def create_infrastructure!
          # Check for existing server and reuse SSH keys for idempotency
          existing_server = compute_client.find_server(prefix)
          if existing_server
            reuse_ssh_keys_from_last_release!
          else
            release.generate_ssh_keypair unless release.ssh_keys_present?
          end
          release.save! if release.changed?

          log_step("firewall")
          firewall = create_firewall!

          log_step("network")
          network = compute_client.find_or_create_network(prefix)

          log_step("server")
          server = create_server!(firewall_id: firewall.id, network_id: network.id)

          release.update!(server_id: server.id.to_s, server_ip: server.public_ipv4)

          log_step("ssh_wait")
          wait_for_ssh!
        end

        def reuse_ssh_keys_from_last_release!
          last_release = Rbrun::Release.where.not(id: release.id)
                                        .where.not(ssh_private_key: nil)
                                        .order(id: :desc)
                                        .first
          return release.generate_ssh_keypair unless last_release

          release.ssh_public_key = last_release.ssh_public_key
          release.ssh_private_key = last_release.ssh_private_key
        end

        def create_firewall!
          rules = [
            { direction: "in", protocol: "tcp", port: "22", source_ips: ["0.0.0.0/0", "::/0"] },
            { direction: "in", protocol: "tcp", port: "80", source_ips: ["0.0.0.0/0", "::/0"] },
            { direction: "in", protocol: "tcp", port: "443", source_ips: ["0.0.0.0/0", "::/0"] },
            { direction: "in", protocol: "tcp", port: "30080", source_ips: ["0.0.0.0/0", "::/0"] },
            { direction: "in", protocol: "tcp", port: "6443", source_ips: ["0.0.0.0/0", "::/0"] }
          ]
          compute_client.find_or_create_firewall(prefix, rules:)
        end

        def create_server!(firewall_id:, network_id:)
          user_data = Providers::CloudInit.generate(ssh_public_key: release.ssh_public_key)
          server_type = config.resolve(config.compute_config.server_type, target:)

          compute_client.find_or_create_server(
            name: prefix,
            server_type:,
            location: config.compute_config.location,
            image: config.compute_config.image,
            user_data:,
            labels: { purpose: "release" },
            firewalls: [firewall_id],
            networks: [network_id]
          )
        end

        def delete_infrastructure!
          log_step("delete_server")
          delete_resource(:server)

          log_step("delete_network")
          delete_resource(:network)

          log_step("delete_firewall")
          delete_resource(:firewall)
        end

        def delete_resource(type)
          finder = "find_#{type}"
          deleter = "delete_#{type}"
          resource = compute_client.public_send(finder, prefix)
          compute_client.public_send(deleter, resource.id) if resource
        end

        def wait_for_ssh!(timeout: 180)
          release.ssh_client.wait_until_ready(max_attempts: timeout / 5, interval: 5)
        end

        def compute_client
          @compute_client ||= config.compute_config.client
        end

        # ─────────────────────────────────────────────────────────────
        # K3s Installation
        # ─────────────────────────────────────────────────────────────

        def install_k3s!
          log_step("k3s_install")
          k3s_installer.install!
        end

        def k3s_installer
          @k3s_installer ||= Kubernetes::K3sInstaller.new(release)
        end

        # ─────────────────────────────────────────────────────────────
        # Volume Provisioning
        # ─────────────────────────────────────────────────────────────

        def needs_volumes?
          config.database?
        end

        def provision_volumes!
          server = compute_client.find_server(prefix)
          location = server.location.split("-").first

          config.database_configs.each do |type, db_config|
            volume_size = config.resolve(db_config.volume_size, target:)
            next unless volume_size

            log_step("volume_#{type}")
            provision_volume!(
              name: "#{prefix}-#{type}",
              size: volume_size.to_i,
              location:,
              mount_path: "#{VOLUME_MOUNT_BASE}/#{prefix}-#{type}"
            )
          end
        end

        def provision_volume!(name:, size:, location:, mount_path:)
          server = compute_client.find_server(prefix)

          volume = compute_client.find_or_create_volume(
            name:,
            size:,
            location:,
            labels: { purpose: "release" }
          )

          unless volume.server_id == server.id
            compute_client.attach_volume(volume_id: volume.id, server_id: server.id)
            sleep 5
          end

          mount_volume!(mount_path)
        end

        def mount_volume!(mount_path)
          run_ssh!(<<~BASH, raise_on_error: false)
            sudo mkdir -p #{mount_path}
            DEVICE=$(lsblk -rno NAME,TYPE | grep disk | grep -v sda | head -1 | awk '{print "/dev/"$1}')
            if [ -n "$DEVICE" ] && ! sudo mountpoint -q #{mount_path}; then
              if ! sudo blkid $DEVICE; then
                sudo mkfs.xfs $DEVICE
              fi
              sudo mount $DEVICE #{mount_path}
              echo "$DEVICE #{mount_path} xfs defaults 0 0" | sudo tee -a /etc/fstab
            fi
          BASH
        end

        def cleanup_volumes!
          volumes = compute_client.list_volumes(label_selector: "purpose=release")
          volumes.each do |volume|
            log_step("delete_volume_#{volume.name}")
            compute_client.detach_volume(volume_id: volume.id) if volume.server_id
            compute_client.delete_volume(volume.id)
          end
        end

        # ─────────────────────────────────────────────────────────────
        # Docker Build
        # ─────────────────────────────────────────────────────────────

        def build_and_push_image!
          clone_repo!

          log_step("docker_build")
          @build_result = docker_builder.build_and_push!(
            context_path: WORKSPACE,
            dockerfile: config.app_config.dockerfile,
            platform: config.app_config.platform
          )

          release.update!(registry_tag: @build_result[:registry_tag])
        end

        def docker_builder
          @docker_builder ||= Kubernetes::DockerBuilder.new(release:, prefix:)
        end

        def clone_repo!
          workspace_exists = run_ssh!("test -d #{WORKSPACE}/.git", raise_on_error: false)[:exit_code] == 0
          action, command = repo_sync_command(workspace_exists:)
          log_step(action)
          run_ssh!(command, timeout: 120)
        end

        # ─────────────────────────────────────────────────────────────
        # Tunnel Setup
        # ─────────────────────────────────────────────────────────────

        def setup_tunnel!
          return unless cloudflare_configured?

          log_step("tunnel_setup")

          cf_client = cloudflare_client
          tunnel = cf_client.find_or_create_tunnel(prefix)
          @tunnel_token = cf_client.get_tunnel_token(tunnel[:id])

          release.update!(tunnel_id: tunnel[:id])

          ingress_rules = build_tunnel_ingress_rules
          cf_client.configure_tunnel_ingress(tunnel[:id], ingress_rules)

          create_tunnel_dns_records!(tunnel[:id])
        end

        def build_tunnel_ingress_rules
          rules = []

          if config.app?
            config.app_config.processes.each do |name, process|
              next unless process.subdomain && process.port
              hostname = "#{process.subdomain}.#{zone}"
              rules << {
                hostname:,
                service: "http://localhost:#{HTTP_NODE_PORT}",
                originRequest: { httpHostHeader: hostname }
              }
            end
          end

          config.service_configs.each do |name, svc_config|
            next unless svc_config.subdomain && svc_config.port
            hostname = "#{svc_config.subdomain}.#{zone}"
            rules << {
              hostname:,
              service: "http://localhost:#{HTTP_NODE_PORT}",
              originRequest: { httpHostHeader: hostname }
            }
          end

          rules << { service: "http_status:404" }
          rules
        end

        def create_tunnel_dns_records!(tunnel_id)
          cf_client = cloudflare_client
          zone_id = cf_client.get_zone_id(zone)

          if config.app?
            config.app_config.processes.each do |name, process|
              next unless process.subdomain
              hostname = "#{process.subdomain}.#{zone}"
              cf_client.ensure_dns_record(zone_id, hostname, tunnel_id)
            end
          end

          config.service_configs.each do |name, svc_config|
            next unless svc_config.subdomain
            hostname = "#{svc_config.subdomain}.#{zone}"
            cf_client.ensure_dns_record(zone_id, hostname, tunnel_id)
          end
        end

        def cleanup_tunnel!
          return unless cloudflare_configured?

          log_step("delete_tunnel")
          cf_client = cloudflare_client
          tunnel = cf_client.find_tunnel(prefix)
          cf_client.delete_tunnel(tunnel[:id]) if tunnel
        end

        def cloudflare_client
          @cloudflare_client ||= config.cloudflare_config.client
        end

        # ─────────────────────────────────────────────────────────────
        # Kubernetes Deployment
        # ─────────────────────────────────────────────────────────────

        def deploy_kubernetes!
          log_step("deploy_manifests")

          generator = Generators::K3s.new(
            config,
            prefix:,
            zone:,
            target:,
            db_password: existing_db_password || SecureRandom.hex(16),
            registry_tag: @build_result&.dig(:registry_tag),
            tunnel_token: @tunnel_token
          )

          kubectl_client.apply(generator.generate)
        end

        def existing_db_password
          result = run_ssh!(
            "kubectl get secret #{prefix}-postgres-secret -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d",
            raise_on_error: false
          )
          result.output.strip.presence
        end

        def wait_for_rollout!
          log_step("wait_rollout")

          config.database_configs.each_key do |type|
            kubectl_client.rollout_status("#{prefix}-#{type}", timeout: 300)
          end

          config.service_configs.each_key do |name|
            kubectl_client.rollout_status("#{prefix}-#{name}", timeout: 120)
          end

          if config.app?
            config.app_config.processes.each_key do |name|
              kubectl_client.rollout_status("#{prefix}-#{name}", timeout: 300)
            end
          end
        end

        def cleanup_kubernetes!
          log_step("cleanup_k8s")

          kubectl_client.delete_resource("deployment", "#{prefix}-cloudflared")

          if config.app?
            config.app_config.processes.each_key do |name|
              kubectl_client.delete_resource("deployment", "#{prefix}-#{name}")
              kubectl_client.delete_resource("service", "#{prefix}-#{name}")
              kubectl_client.delete_resource("ingress", "#{prefix}-#{name}")
            end
          end

          config.service_configs.each_key do |name|
            kubectl_client.delete_resource("deployment", "#{prefix}-#{name}")
            kubectl_client.delete_resource("service", "#{prefix}-#{name}")
            kubectl_client.delete_resource("ingress", "#{prefix}-#{name}")
          end

          config.database_configs.each_key do |type|
            kubectl_client.delete_resource("deployment", "#{prefix}-#{type}")
            kubectl_client.delete_resource("service", "#{prefix}-#{type}")
          end

          kubectl_client.delete_resource("secret", "#{prefix}-app-secret")
        end

        def kubectl_client
          @kubectl_client ||= Kubernetes::Kubectl.new(release)
        end

        def run_ssh!(command, raise_on_error: true, timeout: 300)
          release.run_ssh!(command, raise_on_error:, timeout:)
        end

        def log_step(category)
          release.command_executions.create!(kind: "exec", command: category, category:)
          puts "      [release:#{category}]"
        end
    end
  end
end
