# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Providers
    class ScalewayClientTest < ActiveSupport::TestCase
      def setup
        super
        WebMock.reset!

        @api_key = "test-scaleway-key"
        @project_id = "test-project-id"
        @zone = "fr-par-1"
        @client = Scaleway::Client.new(
          api_key: @api_key,
          project_id: @project_id,
          zone: @zone
        )
      end

      # ─────────────────────────────────────────────────────────────────
      # Initialization
      # ─────────────────────────────────────────────────────────────────

      test "raises error without api_key" do
        assert_raises(Rbrun::Error) do
          Scaleway::Client.new(api_key: nil, project_id: @project_id)
        end
      end

      test "raises error without project_id" do
        assert_raises(Rbrun::Error) do
          Scaleway::Client.new(api_key: @api_key, project_id: nil)
        end
      end

      test "uses default zone" do
        client = Scaleway::Client.new(api_key: @api_key, project_id: @project_id)
        stub_servers_list([])
        client.list_servers
        assert_requested(:get, /zones\/fr-par-1/)
      end

      # ─────────────────────────────────────────────────────────────────
      # Servers
      # ─────────────────────────────────────────────────────────────────

      test "find_server returns nil when not found" do
        stub_servers_list([])
        assert_nil @client.find_server("nonexistent")
      end

      test "find_server returns server when found" do
        stub_servers_list([server_data])
        server = @client.find_server("test-server")

        assert_equal "server-123", server.id
        assert_equal "test-server", server.name
        assert_equal "running", server.status
        assert_equal "1.2.3.4", server.public_ipv4
      end

      test "list_servers returns all servers" do
        stub_servers_list([server_data, server_data(id: "server-456", name: "other")])
        servers = @client.list_servers

        assert_equal 2, servers.size
      end

      test "get_server returns server by id" do
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .with(headers: { "X-Auth-Token" => @api_key })
          .to_return(status: 200, body: { server: server_data }.to_json, headers: json_headers)

        server = @client.get_server("server-123")
        assert_equal "server-123", server.id
      end

      test "get_server returns nil when not found" do
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/nonexistent")
          .to_return(status: 404, body: { message: "not found" }.to_json, headers: json_headers)

        assert_nil @client.get_server("nonexistent")
      end

      test "create_server creates and powers on" do
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
          .with(
            body: hash_including(name: "new-server", commercial_type: "DEV1-S", project: @project_id),
            headers: { "X-Auth-Token" => @api_key }
          )
          .to_return(status: 201, body: { server: server_data(name: "new-server") }.to_json, headers: json_headers)

        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123/action")
          .with(body: { action: "poweron" })
          .to_return(status: 200, body: { task: { id: "task-1" } }.to_json, headers: json_headers)

        server = @client.create_server(name: "new-server", commercial_type: "DEV1-S", image: "ubuntu_jammy")

        assert_equal "server-123", server.id
        assert_requested(:post, /servers\/server-123\/action/)
      end

      test "find_or_create_server returns existing" do
        stub_servers_list([server_data])
        server = @client.find_or_create_server(name: "test-server", commercial_type: "DEV1-S", image: "ubuntu_jammy")

        assert_equal "server-123", server.id
        assert_not_requested(:post, /\/servers$/)
      end

      test "power_on sends poweron action" do
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123/action")
          .with(body: { action: "poweron" })
          .to_return(status: 200, body: { task: {} }.to_json, headers: json_headers)

        @client.power_on("server-123")
        assert_requested(:post, /action/, body: { action: "poweron" })
      end

      test "power_off sends poweroff action" do
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123/action")
          .with(body: { action: "poweroff" })
          .to_return(status: 200, body: { task: {} }.to_json, headers: json_headers)

        @client.power_off("server-123")
        assert_requested(:post, /action/, body: { action: "poweroff" })
      end

      test "wait_for_server returns when status is running" do
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(status: 200, body: { server: server_data(state: "running") }.to_json, headers: json_headers)

        server = @client.wait_for_server("server-123", max_attempts: 1, interval: 0)

        assert_equal "server-123", server.id
        assert_equal "running", server.status
      end

      test "wait_for_server polls until running" do
        # First call returns starting, second returns running
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(
            { status: 200, body: { server: server_data(state: "starting") }.to_json, headers: json_headers },
            { status: 200, body: { server: server_data(state: "running") }.to_json, headers: json_headers }
          )

        server = @client.wait_for_server("server-123", max_attempts: 3, interval: 0)

        assert_equal "running", server.status
      end

      test "delete_server stops running server before deletion" do
        # get_server returns running
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(
            { status: 200, body: { server: server_data(state: "running") }.to_json, headers: json_headers },
            { status: 200, body: { server: server_data(state: "stopped") }.to_json, headers: json_headers }
          )

        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123/action")
          .with(body: { action: "poweroff" })
          .to_return(status: 200, body: { task: {} }.to_json, headers: json_headers)

        stub_request(:delete, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(status: 204)

        @client.delete_server("server-123")

        assert_requested(:post, /action/, body: { action: "poweroff" })
        assert_requested(:delete, /servers\/server-123/)
      end

      test "delete_server skips poweroff for stopped server" do
        stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(status: 200, body: { server: server_data(state: "stopped") }.to_json, headers: json_headers)

        stub_request(:delete, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/server-123")
          .to_return(status: 204)

        @client.delete_server("server-123")

        assert_not_requested(:post, /action/)
        assert_requested(:delete, /servers\/server-123/)
      end

      # ─────────────────────────────────────────────────────────────────
      # SSH Keys
      # ─────────────────────────────────────────────────────────────────

      test "find_ssh_key returns nil when not found" do
        stub_ssh_keys_list([])
        assert_nil @client.find_ssh_key("nonexistent")
      end

      test "find_ssh_key returns key when found" do
        stub_ssh_keys_list([ssh_key_data])
        key = @client.find_ssh_key("test-key")

        assert_equal "key-123", key.id
        assert_equal "test-key", key.name
      end

      test "find_or_create_ssh_key creates when not found" do
        stub_ssh_keys_list([])
        stub_request(:post, "https://api.scaleway.com/iam/v1alpha1/ssh-keys")
          .with(body: hash_including(name: "new-key", project_id: @project_id))
          .to_return(status: 201, body: { ssh_key: ssh_key_data(name: "new-key") }.to_json, headers: json_headers)

        key = @client.find_or_create_ssh_key(name: "new-key", public_key: "ssh-rsa AAAA...")
        assert_equal "key-123", key.id
      end

      test "list_ssh_keys returns all keys" do
        stub_ssh_keys_list([ssh_key_data, ssh_key_data(id: "key-456", name: "other")])
        keys = @client.list_ssh_keys

        assert_equal 2, keys.size
      end

      test "delete_ssh_key sends delete request" do
        stub_request(:delete, "https://api.scaleway.com/iam/v1alpha1/ssh-keys/key-123")
          .to_return(status: 204)

        @client.delete_ssh_key("key-123")
        assert_requested(:delete, /ssh-keys\/key-123/)
      end

      # ─────────────────────────────────────────────────────────────────
      # Security Groups
      # ─────────────────────────────────────────────────────────────────

      test "find_security_group returns nil when not found" do
        stub_security_groups_list([])
        assert_nil @client.find_security_group("nonexistent")
      end

      test "find_security_group returns group when found" do
        stub_security_groups_list([security_group_data])
        sg = @client.find_security_group("test-sg")

        assert_equal "sg-123", sg.id
        assert_equal "test-sg", sg.name
      end

      test "find_or_create_security_group creates when not found" do
        stub_security_groups_list([])
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
          .with(body: hash_including(name: "new-sg", project: @project_id))
          .to_return(status: 201, body: { security_group: security_group_data(name: "new-sg") }.to_json, headers: json_headers)

        sg = @client.find_or_create_security_group(name: "new-sg")
        assert_equal "sg-123", sg.id
      end

      test "add_security_group_rule creates rule" do
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups/sg-123/rules")
          .with(body: hash_including(direction: "inbound", protocol: "TCP", dest_port_from: 22))
          .to_return(status: 201, body: { rule: { id: "rule-1" } }.to_json, headers: json_headers)

        rule = @client.add_security_group_rule(
          security_group_id: "sg-123",
          direction: "inbound",
          protocol: "TCP",
          dest_port_from: 22
        )
        assert_equal "rule-1", rule["id"]
      end

      # ─────────────────────────────────────────────────────────────────
      # Private Networks
      # ─────────────────────────────────────────────────────────────────

      test "find_private_network returns nil when not found" do
        stub_private_networks_list([])
        assert_nil @client.find_private_network("nonexistent")
      end

      test "find_private_network returns network when found" do
        stub_private_networks_list([private_network_data])
        pn = @client.find_private_network("test-pn")

        assert_equal "pn-123", pn.id
        assert_equal "test-pn", pn.name
      end

      test "find_or_create_private_network creates when not found" do
        stub_private_networks_list([])
        stub_request(:post, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
          .with(body: hash_including(name: "new-pn", project_id: @project_id))
          .to_return(status: 201, body: { private_network: private_network_data(name: "new-pn") }.to_json, headers: json_headers)

        pn = @client.find_or_create_private_network(name: "new-pn")
        assert_equal "pn-123", pn.id
      end

      # ─────────────────────────────────────────────────────────────────
      # Volumes
      # ─────────────────────────────────────────────────────────────────

      test "find_volume returns nil when not found" do
        stub_volumes_list([])
        assert_nil @client.find_volume("nonexistent")
      end

      test "find_volume returns volume when found" do
        stub_volumes_list([volume_data])
        vol = @client.find_volume("test-vol")

        assert_equal "vol-123", vol.id
        assert_equal "test-vol", vol.name
        assert_equal 20, vol.size_gb
      end

      test "create_volume creates with correct size" do
        stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/volumes")
          .with(body: hash_including(name: "new-vol", size: 10_000_000_000, project: @project_id))
          .to_return(status: 201, body: { volume: volume_data(name: "new-vol", size: 10_000_000_000) }.to_json, headers: json_headers)

        vol = @client.create_volume(name: "new-vol", size_gb: 10)
        assert_equal "vol-123", vol.id
      end

      # ─────────────────────────────────────────────────────────────────
      # Images
      # ─────────────────────────────────────────────────────────────────

      test "list_images returns images" do
        stub_request(:get, /\/images/)
          .to_return(status: 200, body: { images: [image_data] }.to_json, headers: json_headers)

        images = @client.list_images
        assert_equal 1, images.size
        assert_equal "Ubuntu 22.04", images.first[:name]
      end

      # ─────────────────────────────────────────────────────────────────
      # Validation
      # ─────────────────────────────────────────────────────────────────

      test "validate_credentials returns true on success" do
        stub_servers_list([])
        assert @client.validate_credentials
      end

      test "validate_credentials raises on unauthorized" do
        stub_request(:get, /\/servers/)
          .to_return(status: 401, body: { message: "unauthorized" }.to_json, headers: json_headers)

        assert_raises(Rbrun::Error) { @client.validate_credentials }
      end

      private

        def json_headers
          { "Content-Type" => "application/json" }
        end

        def stub_servers_list(servers)
          stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
            .with(query: hash_including(project: @project_id))
            .to_return(status: 200, body: { servers: }.to_json, headers: json_headers)
        end

        def stub_ssh_keys_list(keys)
          stub_request(:get, "https://api.scaleway.com/iam/v1alpha1/ssh-keys")
            .with(query: hash_including(project_id: @project_id))
            .to_return(status: 200, body: { ssh_keys: keys }.to_json, headers: json_headers)
        end

        def stub_security_groups_list(groups)
          stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
            .with(query: hash_including(project: @project_id))
            .to_return(status: 200, body: { security_groups: groups }.to_json, headers: json_headers)
        end

        def stub_private_networks_list(networks)
          stub_request(:get, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
            .with(query: hash_including(project_id: @project_id))
            .to_return(status: 200, body: { private_networks: networks }.to_json, headers: json_headers)
        end

        def stub_volumes_list(volumes)
          stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/volumes")
            .with(query: hash_including(project: @project_id))
            .to_return(status: 200, body: { volumes: }.to_json, headers: json_headers)
        end

        def server_data(id: "server-123", name: "test-server", state: "running")
          {
            "id" => id,
            "name" => name,
            "state" => state,
            "public_ip" => { "address" => "1.2.3.4" },
            "private_ip" => "10.0.0.1",
            "commercial_type" => "DEV1-S",
            "image" => { "name" => "Ubuntu 22.04" },
            "zone" => "fr-par-1",
            "tags" => [],
            "creation_date" => "2024-01-01T00:00:00Z",
            "volumes" => {}
          }
        end

        def ssh_key_data(id: "key-123", name: "test-key")
          {
            "id" => id,
            "name" => name,
            "fingerprint" => "aa:bb:cc:dd",
            "public_key" => "ssh-rsa AAAA...",
            "created_at" => "2024-01-01T00:00:00Z"
          }
        end

        def security_group_data(id: "sg-123", name: "test-sg")
          {
            "id" => id,
            "name" => name,
            "inbound_default_policy" => "drop",
            "outbound_default_policy" => "accept",
            "servers" => [],
            "creation_date" => "2024-01-01T00:00:00Z"
          }
        end

        def private_network_data(id: "pn-123", name: "test-pn")
          {
            "id" => id,
            "name" => name,
            "subnets" => [],
            "region" => "fr-par",
            "created_at" => "2024-01-01T00:00:00Z"
          }
        end

        def volume_data(id: "vol-123", name: "test-vol", size: 20_000_000_000)
          {
            "id" => id,
            "name" => name,
            "size" => size,
            "volume_type" => "b_ssd",
            "state" => "available",
            "server" => nil,
            "zone" => "fr-par-1",
            "creation_date" => "2024-01-01T00:00:00Z"
          }
        end

        def image_data
          {
            "id" => "img-123",
            "name" => "Ubuntu 22.04",
            "arch" => "x86_64",
            "state" => "available"
          }
        end
    end
  end
end
