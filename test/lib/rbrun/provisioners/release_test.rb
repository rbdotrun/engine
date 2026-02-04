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
    end
  end
end
