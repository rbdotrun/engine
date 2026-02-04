# frozen_string_literal: true

module Rbrun
  module Providers
    module Scaleway
      # Scaleway Cloud API Client
      #
      # Provides compute server provisioning for sandbox environments.
      # API docs: https://www.scaleway.com/en/developers/api/instance/
      class Client < Rbrun::BaseClient
        BASE_URL = "https://api.scaleway.com"

        def initialize(api_key:, project_id:, zone: "fr-par-1")
          @api_key = api_key
          @project_id = project_id
          @zone = zone
          raise Error, "Scaleway API key not configured" if @api_key.blank?
          raise Error, "Scaleway project ID not configured" if @project_id.blank?
          super(timeout: 300)
        end

        # ─────────────────────────────────────────────────────────────────
        # Servers (Instances)
        # ─────────────────────────────────────────────────────────────────

        # Find or create a server (idempotent).
        def find_or_create_server(name:, commercial_type:, image:, tags: [], security_group_id: nil)
          existing = find_server(name)
          return existing if existing

          create_server(name:, commercial_type:, image:, tags:, security_group_id:)
        end

        # Create a new server.
        def create_server(name:, commercial_type:, image:, tags: [], security_group_id: nil)
          payload = {
            name:,
            commercial_type:,
            image:,
            project: @project_id,
            tags: tags || []
          }
          payload[:security_group] = security_group_id if security_group_id

          response = post(instance_path("/servers"), payload)
          server = to_server(response["server"])

          # Scaleway requires explicit power on after creation
          power_on(server.id)
          server
        end

        # Get server by ID.
        def get_server(id)
          response = get(instance_path("/servers/#{id}"))
          to_server(response["server"])
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Find server by name.
        def find_server(name)
          response = get(instance_path("/servers"), name:, project: @project_id)
          server = response["servers"]&.find { |s| s["name"] == name }
          server ? to_server(server) : nil
        end

        # List all servers.
        def list_servers(tags: nil)
          params = { project: @project_id }
          params[:tags] = tags.join(",") if tags&.any?
          response = get(instance_path("/servers"), params)
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
          server = get_server(id)
          return nil unless server

          # Must be stopped before deletion
          if server.status == "running"
            power_off(id)
            wait_for_server_stopped(id)
          end

          # Delete attached volumes
          full_server = get(instance_path("/servers/#{id}"))["server"]
          full_server["volumes"]&.each_value do |vol|
            delete_volume(vol["id"]) if vol["id"]
          rescue StandardError
            # Ignore volume cleanup errors
          end

          delete(instance_path("/servers/#{id}"))
        end

        # Power on a server.
        def power_on(id)
          post(instance_path("/servers/#{id}/action"), { action: "poweron" })
        end

        # Power off a server (hard shutdown).
        def power_off(id)
          post(instance_path("/servers/#{id}/action"), { action: "poweroff" })
        end

        # Reboot a server.
        def reboot(id)
          post(instance_path("/servers/#{id}/action"), { action: "reboot" })
        end

        # ─────────────────────────────────────────────────────────────────
        # SSH Keys
        # ─────────────────────────────────────────────────────────────────

        # Find or create an SSH key (idempotent).
        def find_or_create_ssh_key(name:, public_key:)
          existing = find_ssh_key(name)
          return existing if existing

          response = post(iam_path("/ssh-keys"), {
            name:,
            public_key:,
            project_id: @project_id
          })
          to_ssh_key(response["ssh_key"])
        end

        # Find SSH key by name.
        def find_ssh_key(name)
          response = get(iam_path("/ssh-keys"), project_id: @project_id)
          key = response["ssh_keys"]&.find { |k| k["name"] == name }
          key ? to_ssh_key(key) : nil
        end

        # List all SSH keys.
        def list_ssh_keys
          response = get(iam_path("/ssh-keys"), project_id: @project_id)
          response["ssh_keys"].map { |k| to_ssh_key(k) }
        end

        # Delete an SSH key.
        def delete_ssh_key(id)
          delete(iam_path("/ssh-keys/#{id}"))
        end

        # ─────────────────────────────────────────────────────────────────
        # Security Groups (Scaleway's firewall equivalent)
        # ─────────────────────────────────────────────────────────────────

        # Find or create a security group.
        def find_or_create_security_group(name:, inbound_default_policy: "drop", outbound_default_policy: "accept")
          existing = find_security_group(name)
          return existing if existing

          response = post(instance_path("/security_groups"), {
            name:,
            project: @project_id,
            inbound_default_policy:,
            outbound_default_policy:
          })
          to_security_group(response["security_group"])
        end

        # Find security group by name.
        def find_security_group(name)
          response = get(instance_path("/security_groups"), name:, project: @project_id)
          sg = response["security_groups"]&.find { |g| g["name"] == name }
          sg ? to_security_group(sg) : nil
        end

        # List all security groups.
        def list_security_groups
          response = get(instance_path("/security_groups"), project: @project_id)
          response["security_groups"].map { |sg| to_security_group(sg) }
        end

        # Add a rule to a security group.
        def add_security_group_rule(security_group_id:, direction:, protocol:, dest_port_from: nil, dest_port_to: nil, ip_range: "0.0.0.0/0", action: "accept")
          payload = {
            direction:,
            protocol:,
            ip_range:,
            action:
          }
          payload[:dest_port_from] = dest_port_from if dest_port_from
          payload[:dest_port_to] = dest_port_to || dest_port_from if dest_port_from

          response = post(instance_path("/security_groups/#{security_group_id}/rules"), payload)
          response["rule"]
        end

        # Delete a security group.
        def delete_security_group(id)
          delete(instance_path("/security_groups/#{id}"))
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # ─────────────────────────────────────────────────────────────────
        # Private Networks (VPC)
        # ─────────────────────────────────────────────────────────────────

        # Find or create a private network.
        def find_or_create_private_network(name:, subnets: nil)
          existing = find_private_network(name)
          return existing if existing

          payload = {
            name:,
            project_id: @project_id,
            region: zone_to_region(@zone)
          }
          payload[:subnets] = subnets if subnets

          response = post(vpc_path("/private-networks"), payload)
          to_private_network(response["private_network"])
        end

        # Find private network by name.
        def find_private_network(name)
          response = get(vpc_path("/private-networks"), name:, project_id: @project_id)
          pn = response["private_networks"]&.find { |n| n["name"] == name }
          pn ? to_private_network(pn) : nil
        end

        # List all private networks.
        def list_private_networks
          response = get(vpc_path("/private-networks"), project_id: @project_id)
          response["private_networks"].map { |pn| to_private_network(pn) }
        end

        # Delete a private network.
        def delete_private_network(id)
          delete(vpc_path("/private-networks/#{id}"))
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Attach server to private network.
        def attach_server_to_private_network(server_id:, private_network_id:)
          post(instance_path("/servers/#{server_id}/private_nics"), {
            private_network_id:
          })
        end

        # Detach server from private network.
        def detach_server_from_private_network(server_id:, private_nic_id:)
          delete(instance_path("/servers/#{server_id}/private_nics/#{private_nic_id}"))
        end

        # ─────────────────────────────────────────────────────────────────
        # Volumes
        # ─────────────────────────────────────────────────────────────────

        # Create a volume.
        def create_volume(name:, size_gb:, volume_type: "b_ssd")
          response = post(instance_path("/volumes"), {
            name:,
            project: @project_id,
            size: size_gb * 1_000_000_000, # Convert GB to bytes
            volume_type:
          })
          to_volume(response["volume"])
        end

        # Find volume by name.
        def find_volume(name)
          response = get(instance_path("/volumes"), name:, project: @project_id)
          vol = response["volumes"]&.find { |v| v["name"] == name }
          vol ? to_volume(vol) : nil
        end

        # Get volume by ID.
        def get_volume(id)
          response = get(instance_path("/volumes/#{id}"))
          to_volume(response["volume"])
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # Delete a volume.
        def delete_volume(id)
          delete(instance_path("/volumes/#{id}"))
        rescue ApiError => e
          raise unless e.not_found?
          nil
        end

        # ─────────────────────────────────────────────────────────────────
        # Images
        # ─────────────────────────────────────────────────────────────────

        # List available images.
        def list_images(name: nil, arch: "x86_64")
          params = { arch: }
          params[:name] = name if name
          response = get(instance_path("/images"), params)
          response["images"].map do |img|
            {
              id: img["id"],
              name: img["name"],
              arch: img["arch"],
              state: img["state"]
            }
          end
        end

        # Find Ubuntu image.
        def find_ubuntu_image(version: "22.04")
          images = list_images(name: "Ubuntu #{version}")
          images.find { |img| img[:state] == "available" }
        end

        # ─────────────────────────────────────────────────────────────────
        # Instance Types
        # ─────────────────────────────────────────────────────────────────

        # List available instance types.
        def list_instance_types
          response = get(instance_path("/products/servers"))
          response["servers"].map do |name, details|
            {
              name:,
              ncpus: details["ncpus"],
              ram: details["ram"],
              hourly_price: details.dig("hourly_price"),
              volumes_constraint: details["volumes_constraint"]
            }
          end
        end

        # ─────────────────────────────────────────────────────────────────
        # Validation
        # ─────────────────────────────────────────────────────────────────

        # Validate API credentials.
        def validate_credentials
          get(instance_path("/servers"), project: @project_id)
          true
        rescue ApiError => e
          raise Error, "Scaleway credentials invalid: #{e.message}" if e.unauthorized?
          raise
        end

        private

          def instance_path(path)
            "/instance/v1/zones/#{@zone}#{path}"
          end

          def iam_path(path)
            "/iam/v1alpha1#{path}"
          end

          def vpc_path(path)
            region = zone_to_region(@zone)
            "/vpc/v2/regions/#{region}#{path}"
          end

          def zone_to_region(zone)
            # fr-par-1 -> fr-par, nl-ams-1 -> nl-ams, etc.
            zone.sub(/-\d+$/, "")
          end

          def auth_headers
            { "X-Auth-Token" => @api_key }
          end

          def wait_for_server_stopped(id, max_attempts: 30, interval: 5)
            max_attempts.times do
              server = get_server(id)
              return server if server.nil? || server.status == "stopped"
              sleep(interval)
            end
            raise Error, "Server #{id} did not stop after #{max_attempts} attempts"
          end

          def to_server(data)
            Types::Server.new(
              id: data["id"],
              name: data["name"],
              status: data["state"],
              public_ipv4: data.dig("public_ip", "address"),
              private_ipv4: data.dig("private_ip"),
              instance_type: data["commercial_type"],
              image: data.dig("image", "name"),
              location: data["zone"],
              labels: (data["tags"] || []).to_h { |t| [t, true] },
              created_at: data["creation_date"]
            )
          end

          def to_ssh_key(data)
            Types::SshKey.new(
              id: data["id"],
              name: data["name"],
              fingerprint: data["fingerprint"],
              public_key: data["public_key"],
              created_at: data["created_at"]
            )
          end

          def to_security_group(data)
            Types::Firewall.new(
              id: data["id"],
              name: data["name"],
              rules: data["rules"] || [],
              created_at: data["creation_date"]
            )
          end

          def to_private_network(data)
            Types::Network.new(
              id: data["id"],
              name: data["name"],
              ip_range: nil,
              subnets: data["subnets"] || [],
              location: data["region"],
              created_at: data["created_at"]
            )
          end

          def to_volume(data)
            Types::Volume.new(
              id: data["id"],
              name: data["name"],
              size_gb: data["size"].to_i / 1_000_000_000,
              volume_type: data["volume_type"],
              status: data["state"],
              server_id: data.dig("server", "id"),
              location: data["zone"],
              created_at: data["creation_date"]
            )
          end
      end
    end
  end
end
