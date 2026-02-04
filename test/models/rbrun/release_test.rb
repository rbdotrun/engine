# frozen_string_literal: true

require "test_helper"

module Rbrun
  class ReleaseTest < ActiveSupport::TestCase
    def setup
      super
      Rbrun.reset_configuration!
      Rbrun.configuration.git do |g|
        g.pat = "token"
        g.repo = "org/myapp"
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Default Values
    # ─────────────────────────────────────────────────────────────

    test "defaults environment to production" do
      release = Release.create!
      assert_equal "production", release.environment
    end

    test "defaults branch to main" do
      release = Release.create!
      assert_equal "main", release.branch
    end

    test "can set custom environment" do
      release = Release.create!(environment: "staging")
      assert_equal "staging", release.environment
    end

    test "can set custom branch" do
      release = Release.create!(branch: "feature-x")
      assert_equal "feature-x", release.branch
    end

    # ─────────────────────────────────────────────────────────────
    # Scopes
    # ─────────────────────────────────────────────────────────────

    test "for_environment scope filters by environment" do
      Release.create!(environment: "production")
      Release.create!(environment: "staging")
      Release.create!(environment: "production")

      assert_equal 2, Release.for_environment("production").count
      assert_equal 1, Release.for_environment("staging").count
    end

    # ─────────────────────────────────────────────────────────────
    # Prefix
    # ─────────────────────────────────────────────────────────────

    test "prefix returns app_name-environment" do
      release = Release.create!(environment: "production")
      assert_equal "myapp-production", release.prefix
    end

    test "prefix uses environment from release" do
      release = Release.create!(environment: "staging")
      assert_equal "myapp-staging", release.prefix
    end

    # ─────────────────────────────────────────────────────────────
    # Class Methods
    # ─────────────────────────────────────────────────────────────

    test "current returns latest deployed release for environment" do
      old_prod = Release.create!(environment: "production", state: "deployed", deployed_at: 1.day.ago)
      new_prod = Release.create!(environment: "production", state: "deployed", deployed_at: 1.hour.ago)
      staging = Release.create!(environment: "staging", state: "deployed", deployed_at: Time.current)

      assert_equal new_prod, Release.current(environment: "production")
      assert_equal staging, Release.current(environment: "staging")
    end

    test "current defaults to production environment" do
      prod = Release.create!(environment: "production", state: "deployed", deployed_at: Time.current)
      Release.create!(environment: "staging", state: "deployed", deployed_at: Time.current)

      assert_equal prod, Release.current
    end
  end
end
