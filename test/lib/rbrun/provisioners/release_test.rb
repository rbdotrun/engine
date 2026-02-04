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
    end
  end
end
