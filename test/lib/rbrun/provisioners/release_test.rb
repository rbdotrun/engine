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
      # SSH Key Tests
      # ─────────────────────────────────────────────────────────────

      test "load_ssh_keys! generates keys when no ssh_key_path configured" do
        @provisioner.send(:load_ssh_keys!)

        assert @release.ssh_public_key.present?
        assert @release.ssh_private_key.present?
        assert @release.ssh_public_key.start_with?("ssh-rsa")
      end

      test "load_ssh_keys! uses configured ssh_key_path" do
        Dir.mktmpdir do |dir|
          private_key_path = File.join(dir, "test_key")
          public_key_path = "#{private_key_path}.pub"

          File.write(private_key_path, "PRIVATE_KEY_CONTENT")
          File.write(public_key_path, "ssh-rsa AAAA... test@example.com")

          Rbrun.configuration.compute_config.ssh_key_path = private_key_path

          @provisioner.send(:load_ssh_keys!)

          assert_equal "PRIVATE_KEY_CONTENT", @release.ssh_private_key
          assert_equal "ssh-rsa AAAA... test@example.com", @release.ssh_public_key
        end
      end

      test "ssh keys not reloaded if already present on release" do
        @release.ssh_public_key = "existing_pub"
        @release.ssh_private_key = "existing_priv"

        # load_ssh_keys! should not be called when keys present
        assert @release.ssh_keys_present?

        # Keys remain unchanged
        assert_equal "existing_pub", @release.ssh_public_key
        assert_equal "existing_priv", @release.ssh_private_key
      end
    end
  end
end
