# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Ssh
    class ClientTest < ActiveSupport::TestCase
      def setup
        super
        @host = "192.168.1.100"
        @private_key = TEST_SSH_KEY.private_key
        @user = "deploy"
      end

      # ─────────────────────────────────────────────────────────────────
      # Initialization
      # ─────────────────────────────────────────────────────────────────

      test "initializes with required parameters" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_equal @host, client.host
        assert_equal "root", client.user
      end

      test "initializes with custom user" do
        client = Client.new(host: @host, private_key: @private_key, user: @user)

        assert_equal @user, client.user
      end

      test "initializes with custom port" do
        client = Client.new(host: @host, private_key: @private_key, port: 2222)

        assert_equal @host, client.host
      end

      test "initializes with strict host key checking" do
        client = Client.new(host: @host, private_key: @private_key, strict_host_key_checking: true)

        assert_equal @host, client.host
      end

      # ─────────────────────────────────────────────────────────────────
      # Error Classes
      # ─────────────────────────────────────────────────────────────────

      test "CommandError stores exit_code and output" do
        error = Client::CommandError.new("failed", exit_code: 127, output: "command not found")

        assert_equal 127, error.exit_code
        assert_equal "command not found", error.output
        assert_equal "failed", error.message
      end

      test "error hierarchy - AuthenticationError inherits from Error" do
        assert Client::AuthenticationError < Client::Error
      end

      test "error hierarchy - ConnectionError inherits from Error" do
        assert Client::ConnectionError < Client::Error
      end

      test "error hierarchy - CommandError inherits from Error" do
        assert Client::CommandError < Client::Error
      end

      test "Error inherits from StandardError" do
        assert Client::Error < StandardError
      end

      # ─────────────────────────────────────────────────────────────────
      # Execute - Unit tests with mocked SSH
      # ─────────────────────────────────────────────────────────────────

      test "execute returns hash with output and exit_code" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh(client, output: "hello", exit_code: 0) do
          client.execute("echo hello")
        end

        assert_kind_of Hash, result
        assert_equal "hello", result[:output]
        assert_equal 0, result[:exit_code]
      end

      test "execute raises CommandError on non-zero exit" do
        client = Client.new(host: @host, private_key: @private_key)

        error = assert_raises(Client::CommandError) do
          with_mocked_ssh(client, output: "error", exit_code: 1) do
            client.execute("fail")
          end
        end

        assert_equal 1, error.exit_code
        assert_equal "error", error.output
      end

      test "execute with raise_on_error false returns result" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh(client, output: "error", exit_code: 1) do
          client.execute("fail", raise_on_error: false)
        end

        assert_equal 1, result[:exit_code]
        assert_equal "error", result[:output]
      end

      test "execute yields each line of output" do
        client = Client.new(host: @host, private_key: @private_key)
        lines = []

        with_mocked_ssh(client, output: "line1\nline2\nline3", exit_code: 0) do
          client.execute("cmd") { |line| lines << line }
        end

        assert_equal %w[line1 line2 line3], lines
      end

      # ─────────────────────────────────────────────────────────────────
      # Execute Ignore Errors
      # ─────────────────────────────────────────────────────────────────

      test "execute_ignore_errors returns result on success" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh(client, output: "ok", exit_code: 0) do
          client.execute_ignore_errors("cmd")
        end

        assert_equal "ok", result[:output]
      end

      test "execute_ignore_errors returns nil on error" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh_error(client, Client::Error.new("fail")) do
          client.execute_ignore_errors("cmd")
        end

        assert_nil result
      end

      # ─────────────────────────────────────────────────────────────────
      # Available
      # ─────────────────────────────────────────────────────────────────

      test "available? returns true when SSH responds" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh_exec(client, "ok") do
          client.available?
        end

        assert result
      end

      test "available? returns false on connection error" do
        client = Client.new(host: @host, private_key: @private_key)

        result = with_mocked_ssh_error(client, Errno::ECONNREFUSED.new) do
          client.available?
        end

        refute result
      end

      # ─────────────────────────────────────────────────────────────────
      # File Operations
      # ─────────────────────────────────────────────────────────────────

      test "read_file returns content on success" do
        client = Client.new(host: @host, private_key: @private_key)

        content = with_mocked_ssh(client, output: "file content", exit_code: 0) do
          client.read_file("/etc/hosts")
        end

        assert_equal "file content", content
      end

      test "read_file returns nil on failure" do
        client = Client.new(host: @host, private_key: @private_key)

        content = with_mocked_ssh(client, output: "No such file", exit_code: 1) do
          client.read_file("/missing")
        end

        assert_nil content
      end

      # ─────────────────────────────────────────────────────────────────
      # Connection Errors
      # ─────────────────────────────────────────────────────────────────

      test "raises AuthenticationError on auth failure" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_raises(Client::AuthenticationError) do
          with_mocked_ssh_error(client, Net::SSH::AuthenticationFailed.new("auth")) do
            client.execute("cmd")
          end
        end
      end

      test "raises ConnectionError on timeout" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_raises(Client::ConnectionError) do
          with_mocked_ssh_error(client, Net::SSH::ConnectionTimeout.new) do
            client.execute("cmd")
          end
        end
      end

      test "raises ConnectionError on refused" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_raises(Client::ConnectionError) do
          with_mocked_ssh_error(client, Errno::ECONNREFUSED.new) do
            client.execute("cmd")
          end
        end
      end

      test "raises ConnectionError on host unreachable" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_raises(Client::ConnectionError) do
          with_mocked_ssh_error(client, Errno::EHOSTUNREACH.new) do
            client.execute("cmd")
          end
        end
      end

      test "raises ConnectionError on socket error" do
        client = Client.new(host: @host, private_key: @private_key)

        assert_raises(Client::ConnectionError) do
          with_mocked_ssh_error(client, SocketError.new("socket")) do
            client.execute("cmd")
          end
        end
      end

      private

        # Mock SSH session for execute() calls
        def with_mocked_ssh(client, output:, exit_code:)
          mock_channel = build_mock_channel(output, exit_code)
          mock_ssh = build_mock_ssh(mock_channel)

          Net::SSH.stub(:start, ->(host, user, opts, &block) { block.call(mock_ssh) }) do
            yield
          end
        end

        # Mock SSH to raise an error
        def with_mocked_ssh_error(client, error)
          Net::SSH.stub(:start, ->(*) { raise error }) do
            yield
          end
        end

        # Mock simple SSH exec! for available? check
        def with_mocked_ssh_exec(client, result)
          mock_ssh = Object.new
          mock_ssh.define_singleton_method(:exec!) { |_| result }

          Net::SSH.stub(:start, ->(host, user, opts, &block) { block.call(mock_ssh) }) do
            yield
          end
        end

        def build_mock_channel(output, exit_code)
          channel = Object.new
          channel.define_singleton_method(:wait) { }
          channel.define_singleton_method(:exec) do |cmd, &block|
            ch = Object.new
            ch.define_singleton_method(:eof!) { }
            ch.define_singleton_method(:on_data) do |&data_block|
              data_block.call(nil, output) if output.present?
            end
            ch.define_singleton_method(:on_extended_data) { |&_| }
            ch.define_singleton_method(:on_request) do |type, &req_block|
              if type == "exit-status"
                data = Object.new
                data.define_singleton_method(:read_long) { exit_code }
                req_block.call(nil, data)
              end
            end
            block.call(ch, true)
          end
          channel
        end

        def build_mock_ssh(channel)
          ssh = Object.new
          ssh.define_singleton_method(:open_channel) do |&block|
            block.call(channel)
            channel
          end
          ssh
        end
    end
  end
end
