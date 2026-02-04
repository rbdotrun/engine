# frozen_string_literal: true

module Rbrun
  module Providers
    module Hetzner
      # Hetzner Cloud API Client
      #
      # Provides compute server provisioning for sandbox environments.
      class Client < Rbrun::BaseClient
        BASE_URL = "https://api.hetzner.cloud/v1"

        # Location to network zone mapping
        NETWORK_ZONES = {
          "fsn1" => "eu-central",
          "nbg1" => "eu-central",
          "hel1" => "eu-central",
          "ash" => "us-east",
          "hil" => "us-west"
        }.freeze

        def initialize(api_key:)
          @api_key = api_key
          raise Error, "Hetzner API key not configured" if @api_key.blank?
          super(timeout: 300)
        end

        # Find or create a server (idempotent).
        def find_or_create_server(name:, server_type:, image: "ubuntu-22.04", location: nil, ssh_keys: [], user_data: nil, labels: {}, firewalls: nil, networks: nil)
          existing = find_server(name)
          return existing if existing

          create_server(name:, server_type:, image:, location:, ssh_keys:, user_data:, labels:, firewalls:, networks:)
        end

        # Create a new server.
        def create_server(name:, server_type:, image: "ubuntu-22.04", location: nil, ssh_keys: [], user_data: nil, labels: {}, firewalls: nil, networks: nil)
          payload = {
            name:,
            server_type:,
            image:,
            location:,
            start_after_create: true,
            labels: labels || {}
          }
          payload[:ssh_keys] = ssh_keys if ssh_keys.any?
          payload[:user_data] = user_data if user_data.present?
          payload[:firewalls] = firewalls.map { |id| { firewall: id.to_i } } if firewalls&.any?
          payload[:networks] = networks.map(&:to_i) if networks&.any?

          response = post("/servers", payload)
          to_server(response["server"])
        end

        # Get server by ID.
        def get_server(id)
          response = get("/servers/#{id.to_i}")
          to_server(response["server"])
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Find server by name.
        def find_server(name)
          response = get("/servers", name:)
          server = response["servers"]&.first
          server ? to_server(server) : nil
        end

        # List all servers.
        def list_servers(label_selector: nil)
          params = {}
          params[:label_selector] = label_selector if label_selector
          response = get("/servers", params)
          response["servers"].map { |s| to_server(s) }
        end

        # Wait for server to be running.
        def wait_for_server(id, max_attempts: 60, interval: 5)
          max_attempts.times do
            server = get_server(id)
            return server if server && server.status == "running"
            sleep(interval)
          end
          raise Error, "Server #{id} did not become running after #{max_attempts} attempts"
        end

        # Delete a server.
        def delete_server(id)
          server_id = id.to_i

          begin
            server = get("/servers/#{server_id}")["server"]

            # Remove from firewalls
            get("/firewalls")["firewalls"].each do |fw|
              fw["applied_to"]&.each do |applied|
                next unless applied["type"] == "server" && applied.dig("server", "id") == server_id
                remove_firewall_from_server(fw["id"], server_id)
              rescue StandardError
                # Ignore cleanup errors
              end
            end

            # Detach from networks
            server["private_net"]&.each do |pn|
              detach_server_from_network(server_id, pn["network"])
            rescue StandardError
              # Ignore cleanup errors
            end
          rescue ApiError => e
            return nil if e.not_found?
            raise
          end

          delete("/servers/#{server_id}")
        end

        # Power on a server.
        def power_on(id)
          post("/servers/#{id.to_i}/actions/poweron")
        end

        # Power off a server (hard shutdown).
        def power_off(id)
          post("/servers/#{id.to_i}/actions/poweroff")
        end

        # Shutdown a server (graceful).
        def shutdown(id)
          post("/servers/#{id.to_i}/actions/shutdown")
        end

        # Reboot a server.
        def reboot(id)
          post("/servers/#{id.to_i}/actions/reboot")
        end

        # Find or create an SSH key (idempotent).
        def find_or_create_ssh_key(name:, public_key:)
          existing = find_ssh_key(name)
          return existing if existing

          response = post("/ssh_keys", { name:, public_key: })
          to_ssh_key(response["ssh_key"])
        end

        # Find SSH key by name.
        def find_ssh_key(name)
          response = get("/ssh_keys", name:)
          key = response["ssh_keys"]&.first
          key ? to_ssh_key(key) : nil
        end

        # List all SSH keys.
        def list_ssh_keys
          response = get("/ssh_keys")
          response["ssh_keys"].map { |k| to_ssh_key(k) }
        end

        # Delete an SSH key.
        def delete_ssh_key(id)
          delete("/ssh_keys/#{id.to_i}")
        end

        # List all firewalls.
        def list_firewalls
          response = get("/firewalls")
          response["firewalls"].map { |f| to_firewall(f) }
        end

        # Find or create a private network.
        def find_or_create_network(name, location:, ip_range: "10.0.0.0/16", subnet_range: "10.0.0.0/24")
          existing = find_network(name)
          return existing if existing

          network_zone = NETWORK_ZONES[location] || "eu-central"

          response = post("/networks", {
            name:,
            ip_range:,
            subnets: [{
              type: "cloud",
              ip_range: subnet_range,
              network_zone:
            }]
          })
          to_network(response["network"])
        end

        # Find network by name.
        def find_network(name)
          response = get("/networks", name:)
          network = response["networks"]&.first
          network ? to_network(network) : nil
        end

        # List all networks.
        def list_networks
          response = get("/networks")
          response["networks"].map { |n| to_network(n) }
        end

        # Delete a network.
        def delete_network(id)
          delete("/networks/#{id.to_i}")
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Find or create a firewall.
        def find_or_create_firewall(name, rules: nil)
          existing = find_firewall(name)
          return existing if existing

          rules ||= [
            { direction: "in", protocol: "tcp", port: "22", source_ips: ["0.0.0.0/0", "::/0"] }
          ]

          response = post("/firewalls", { name:, rules: })
          to_firewall(response["firewall"])
        end

        # Find firewall by name.
        def find_firewall(name)
          response = get("/firewalls", name:)
          firewall = response["firewalls"]&.first
          firewall ? to_firewall(firewall) : nil
        end

        # Delete a firewall.
        def delete_firewall(id)
          delete("/firewalls/#{id.to_i}")
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Validate API credentials.
        def validate_credentials
          get("/server_types")
          true
        rescue ApiError => e
          raise Error, "Hetzner credentials invalid: #{e.message}" if e.unauthorized?
          raise
        end

        # List available server types at a location.
        def list_server_types(location:)
          all_types = get("/server_types")["server_types"]
          datacenter = get("/datacenters")["datacenters"].find { |d| d["name"] == location }
          return [] unless datacenter

          available_ids = datacenter.dig("server_types", "available") || []
          all_types.select { |t| available_ids.include?(t["id"]) }.map do |t|
            {
              name: t["name"],
              description: t["description"],
              cores: t["cores"],
              memory: t["memory"],
              disk: t["disk"],
              cpu_type: t["cpu_type"]
            }
          end
        end

        # List available locations/datacenters.
        def list_locations
          get("/datacenters")["datacenters"].map do |d|
            {
              name: d["name"],
              city: d.dig("location", "city"),
              country: d.dig("location", "country"),
              description: d["description"]
            }
          end
        end

        # ═══════════════════════════════════════════════════════════════════
        # Volume Management (for K3s persistent storage)
        # ═══════════════════════════════════════════════════════════════════

        # Find or create a volume (idempotent).
        def find_or_create_volume(name:, size:, location:, labels: {}, format: "xfs")
          existing = find_volume(name)
          return existing if existing

          create_volume(name:, size:, location:, labels:, format:)
        end

        # Create a new volume.
        def create_volume(name:, size:, location:, labels: {}, format: "xfs")
          payload = {
            name:,
            size:,
            location:,
            labels: labels || {},
            automount: false,
            format:
          }

          response = post("/volumes", payload)
          to_volume(response["volume"])
        end

        # Get volume by ID.
        def get_volume(id)
          response = get("/volumes/#{id.to_i}")
          to_volume(response["volume"])
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Find volume by name.
        def find_volume(name)
          response = get("/volumes", name:)
          volume = response["volumes"]&.first
          volume ? to_volume(volume) : nil
        end

        # List all volumes.
        def list_volumes(label_selector: nil)
          params = {}
          params[:label_selector] = label_selector if label_selector
          response = get("/volumes", params)
          response["volumes"].map { |v| to_volume(v) }
        end

        # Attach volume to server.
        # Automatically detaches from current server if attached elsewhere.
        def attach_volume(volume_id:, server_id:, automount: false)
          volume = get_volume(volume_id)

          # Detach first if attached to a different server
          if volume&.server_id.present? && volume.server_id.to_s != server_id.to_s
            detach_volume(volume_id:)
          end

          response = post("/volumes/#{volume_id.to_i}/actions/attach", {
            server: server_id.to_i,
            automount:
          })
          wait_for_action(response["action"]["id"]) if response["action"]
          get_volume(volume_id)
        end

        # Detach volume from server.
        def detach_volume(volume_id:)
          response = post("/volumes/#{volume_id.to_i}/actions/detach")
          wait_for_action(response["action"]["id"]) if response["action"]
        rescue ApiError => e
          raise unless e.message.include?("not attached")
        end

        # Delete a volume.
        def delete_volume(id)
          delete("/volumes/#{id.to_i}")
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Resize a volume (can only increase size).
        def resize_volume(id, size:)
          response = post("/volumes/#{id.to_i}/actions/resize", { size: })
          wait_for_action(response["action"]["id"]) if response["action"]
          get_volume(id)
        end

        # Wait for an action to complete.
        def wait_for_action(action_id, max_attempts: 60, interval: 2)
          max_attempts.times do
            response = get("/actions/#{action_id}")
            status = response.dig("action", "status")
            return true if status == "success"
            raise Error, "Action #{action_id} failed: #{response.dig('action', 'error', 'message')}" if status == "error"
            sleep(interval)
          end
          raise Error, "Action #{action_id} timed out after #{max_attempts * interval} seconds"
        end

        private

          def auth_headers
            {
              "Authorization" => "Bearer #{@api_key}",
              "Content-Type" => "application/json"
            }
          end

          def to_server(data)
            Types::Server.new(
              id: data["id"].to_s,
              name: data["name"],
              status: data["status"],
              public_ipv4: data.dig("public_net", "ipv4", "ip"),
              private_ipv4: data["private_net"]&.first&.dig("ip"),
              instance_type: data.dig("server_type", "name"),
              image: data.dig("image", "name"),
              location: data.dig("datacenter", "name"),
              labels: data["labels"] || {},
              created_at: data["created"]
            )
          end

          def to_ssh_key(data)
            Types::SshKey.new(
              id: data["id"].to_s,
              name: data["name"],
              fingerprint: data["fingerprint"],
              public_key: data["public_key"],
              created_at: data["created"]
            )
          end

          def to_firewall(data)
            Types::Firewall.new(
              id: data["id"].to_s,
              name: data["name"],
              rules: data["rules"] || [],
              created_at: data["created"]
            )
          end

          def to_network(data)
            Types::Network.new(
              id: data["id"].to_s,
              name: data["name"],
              ip_range: data["ip_range"],
              subnets: data["subnets"] || [],
              location: nil,
              created_at: data["created"]
            )
          end

          def remove_firewall_from_server(firewall_id, server_id)
            post("/firewalls/#{firewall_id}/actions/remove_from_resources", {
              remove_from: [{
                type: "server",
                server: { id: server_id }
              }]
            })
          end

          def detach_server_from_network(server_id, network_id)
            post("/servers/#{server_id}/actions/detach_from_network", { network: network_id })
          end

          def to_volume(data)
            Types::Volume.new(
              id: data["id"].to_s,
              name: data["name"],
              size_gb: data["size"],
              volume_type: data["format"] || "xfs",
              status: data["status"],
              server_id: data["server"]&.to_s,
              location: data["location"]["name"],
              device_path: data["linux_device"],
              created_at: data["created"]
            )
          end
      end
    end
  end
end
