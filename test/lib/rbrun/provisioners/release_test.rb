# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Provisioners
    class ReleaseTest < ActiveSupport::TestCase
      def setup
        super
        Rbrun.reset_configuration!
        Rbrun.configuration.compute(:hetzner) { |c| c.api_key = "test_key" }
        Rbrun.configuration.git do |g|
          g.pat = "github_token"
          g.repo = "owner/repo"
        end
        @release = Rbrun::Release.create!
        @provisioner = Release.new(@release)
      end

      test "provisioner initializes with release" do
        assert_equal @release, @provisioner.release
      end

      test "repo_sync_command returns clone when workspace does not exist" do
        action, command = @provisioner.repo_sync_command(workspace_exists: false)

        assert_equal "clone", action
        assert_includes command, "git clone"
        assert_includes command, "owner/repo"
        assert_includes command, "--branch main"
      end

      test "repo_sync_command returns pull when workspace exists" do
        action, command = @provisioner.repo_sync_command(workspace_exists: true)

        assert_equal "pull", action
        assert_includes command, "git fetch"
        assert_includes command, "git checkout main"
        assert_includes command, "git pull origin main"
        refute_includes command, "git clone"
      end

      test "repo_sync_command uses release branch for clone" do
        @release.update!(branch: "feature-x")
        action, command = @provisioner.repo_sync_command(workspace_exists: false)

        assert_includes command, "--branch feature-x"
      end

      test "repo_sync_command uses release branch for pull" do
        @release.update!(branch: "staging")
        action, command = @provisioner.repo_sync_command(workspace_exists: true)

        assert_includes command, "git checkout staging"
        assert_includes command, "git pull origin staging"
      end

      # ─────────────────────────────────────────────────────────────
      # Database Password Tests
      # ─────────────────────────────────────────────────────────────

      test "configured_db_password returns nil when not set" do
        Rbrun.configuration.database(:postgres)

        assert_nil @provisioner.send(:configured_db_password)
      end

      test "configured_db_password returns password when set" do
        Rbrun.configuration.database(:postgres) { |db| db.password = "my_secret_pw" }

        assert_equal "my_secret_pw", @provisioner.send(:configured_db_password)
      end

      test "configured_db_password returns nil when no postgres configured" do
        assert_nil @provisioner.send(:configured_db_password)
      end

      # ─────────────────────────────────────────────────────────────
      # SSH Key Tests (releases use static config keys)
      # ─────────────────────────────────────────────────────────────

      test "ssh_client uses config ssh_private_key" do
        Dir.mktmpdir do |dir|
          private_key_path = File.join(dir, "test_key")
          public_key_path = "#{private_key_path}.pub"

          File.write(private_key_path, "CONFIG_PRIVATE_KEY")
          File.write(public_key_path, "ssh-rsa CONFIG_PUBLIC test@example.com")

          Rbrun.configuration.compute_config.ssh_key_path = private_key_path
          @release.update!(server_ip: "1.2.3.4")

          client = @release.ssh_client
          assert_equal "CONFIG_PRIVATE_KEY", client.instance_variable_get(:@private_key)
        end
      end

      test "config ssh_public_key reads from file" do
        Dir.mktmpdir do |dir|
          private_key_path = File.join(dir, "test_key")
          public_key_path = "#{private_key_path}.pub"

          File.write(private_key_path, "PRIVATE")
          File.write(public_key_path, "ssh-rsa PUBLIC test@example.com")

          Rbrun.configuration.compute_config.ssh_key_path = private_key_path

          assert_equal "ssh-rsa PUBLIC test@example.com", Rbrun.configuration.compute_config.ssh_public_key
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Provision/Redeploy Tests
      # ─────────────────────────────────────────────────────────────

      test "provision! skips if already deployed" do
        @release.update!(state: "deployed")

        # Should not call any provisioning methods
        @provisioner.stub(:create_infrastructure!, -> { raise "should not be called" }) do
          @provisioner.provision! # Should return early, not raise
        end
      end

      test "redeploy! raises if not deployed" do
        @release.update!(state: "pending")

        assert_raises(RuntimeError, "Release not deployed") do
          @provisioner.redeploy!
        end
      end

      test "redeploy! calls deploy_kubernetes!" do
        @release.update!(state: "deployed")

        deploy_called = false
        @provisioner.stub(:build_and_push_image!, -> {}) do
          @provisioner.stub(:deploy_kubernetes!, -> { deploy_called = true }) do
            @provisioner.stub(:wait_for_rollout!, -> {}) do
              @provisioner.redeploy!
            end
          end
        end

        assert deploy_called, "deploy_kubernetes! should be called on redeploy"
      end
    end
  end
end
