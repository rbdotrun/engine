# frozen_string_literal: true

require "test_helper"

module Rbrun
  class ConfigurationTest < ActiveSupport::TestCase
    def setup
      super
      Rbrun.reset_configuration!
      @config = Configuration.new
    end

    # ─────────────────────────────────────────────────────────────
    # Compute Provider Tests
    # ─────────────────────────────────────────────────────────────

    test "#compute creates hetzner config with defaults" do
      @config.compute(:hetzner) { |c| c.api_key = "key" }

      assert_equal :hetzner, @config.compute_config.provider_name
      assert_equal "cpx11", @config.compute_config.server_type
      assert_equal "ash", @config.compute_config.location
      assert_equal "ubuntu-22.04", @config.compute_config.image
    end

    test "#compute creates scaleway config" do
      @config.compute(:scaleway) { |c| c.api_key = "key" }

      assert_equal :scaleway, @config.compute_config.provider_name
    end

    test "#compute raises for unknown provider" do
      error = assert_raises(ArgumentError) { @config.compute(:unknown) }
      assert_match(/Unknown compute provider/, error.message)
    end

    test "hetzner supports self-hosted databases" do
      @config.compute(:hetzner) { |c| c.api_key = "key" }
      assert @config.compute_config.supports_self_hosted?
    end

    test "scaleway supports self-hosted databases" do
      @config.compute(:scaleway) { |c| c.api_key = "key" }
      assert @config.compute_config.supports_self_hosted?
    end

    # ─────────────────────────────────────────────────────────────
    # Unified Database Tests
    # ─────────────────────────────────────────────────────────────

    test "#database creates postgres config" do
      @config.database(:postgres)

      assert @config.database?(:postgres)
      assert_equal :postgres, @config.database_configs[:postgres].type
      assert_equal "postgres:16-alpine", @config.database_configs[:postgres].image
    end

    test "#database creates redis config" do
      @config.database(:redis)

      assert @config.database?(:redis)
      assert_equal :redis, @config.database_configs[:redis].type
      assert_equal "redis:7-alpine", @config.database_configs[:redis].image
    end

    test "#database allows setting volume_size" do
      @config.database(:postgres) do |db|
        db.volume_size = "50Gi"
      end

      assert_equal "50Gi", @config.database_configs[:postgres].volume_size
    end

    test "#database? returns false when no databases configured" do
      refute @config.database?
    end

    test "#database? returns true when databases configured" do
      @config.database(:postgres)
      assert @config.database?
    end

    # ─────────────────────────────────────────────────────────────
    # Unified Service Tests
    # ─────────────────────────────────────────────────────────────

    test "#service creates service config" do
      @config.service(:redis)

      assert @config.service?(:redis)
      assert_equal :redis, @config.service_configs[:redis].name
      assert_equal "redis:7-alpine", @config.service_configs[:redis].image
    end

    test "#service allows setting subdomain" do
      @config.service(:meilisearch) do |s|
        s.subdomain = "search"
      end

      assert_equal "search", @config.service_configs[:meilisearch].subdomain
    end

    test "#service? returns false when no services configured" do
      refute @config.service?
    end

    # ─────────────────────────────────────────────────────────────
    # Unified App Tests
    # ─────────────────────────────────────────────────────────────

    test "#app creates app config with processes" do
      @config.app do |a|
        a.process(:web) do |p|
          p.command = "bin/rails server"
          p.port = 3000
        end
      end

      assert @config.app?
      assert_equal "bin/rails server", @config.app_config.processes[:web].command
      assert_equal 3000, @config.app_config.processes[:web].port
    end

    test "#app allows multiple processes" do
      @config.app do |a|
        a.process(:web) { |p| p.port = 3000 }
        a.process(:worker) { |p| p.command = "bin/jobs" }
      end

      assert_equal 2, @config.app_config.processes.size
      assert @config.app_config.processes.key?(:web)
      assert @config.app_config.processes.key?(:worker)
    end

    test "#app allows setting replicas with hash syntax" do
      @config.app do |a|
        a.process(:web) do |p|
          p.replicas = { sandbox: 1, release: 2 }
        end
      end

      assert_equal({ sandbox: 1, release: 2 }, @config.app_config.processes[:web].replicas)
    end

    # ─────────────────────────────────────────────────────────────
    # Storage Tests
    # ─────────────────────────────────────────────────────────────

    test "#storage creates storage config" do
      @config.storage do |s|
        s.subdomain = "assets"
      end

      assert @config.storage?
      assert_equal "assets", @config.storage_config.subdomain
    end

    test "#storage? returns false when not configured" do
      refute @config.storage?
    end

    # ─────────────────────────────────────────────────────────────
    # Value Resolution Tests
    # ─────────────────────────────────────────────────────────────

    test "#resolve returns value directly for non-hash values" do
      assert_equal "foo", @config.resolve("foo", target: :sandbox)
      assert_equal 42, @config.resolve(42, target: :release)
    end

    test "#resolve extracts sandbox value from hash" do
      value = { sandbox: "dev", release: "prod" }
      assert_equal "dev", @config.resolve(value, target: :sandbox)
    end

    test "#resolve extracts release value from hash" do
      value = { sandbox: "dev", release: "prod" }
      assert_equal "prod", @config.resolve(value, target: :release)
    end

    test "#resolve returns hash as-is if not sandbox/release keyed" do
      value = { foo: "bar" }
      assert_equal value, @config.resolve(value, target: :sandbox)
    end

    # ─────────────────────────────────────────────────────────────
    # Cloudflare Tests
    # ─────────────────────────────────────────────────────────────

    test "#cloudflare yields and returns config" do
      @config.cloudflare do |cf|
        cf.api_token = "cf-token"
        cf.account_id = "cf-account"
        cf.domain = "example.com"
      end

      assert_equal "cf-token", @config.cloudflare_config.api_token
      assert_equal "cf-account", @config.cloudflare_config.account_id
      assert_equal "example.com", @config.cloudflare_config.domain
    end

    test "#cloudflare_configured? returns false when not configured" do
      refute @config.cloudflare_configured?
    end

    test "#cloudflare_configured? returns true when all cloudflare settings present" do
      @config.cloudflare do |cf|
        cf.api_token = "key"
        cf.account_id = "id"
        cf.domain = "zone"
      end
      assert @config.cloudflare_configured?
    end

    # ─────────────────────────────────────────────────────────────
    # Git Config Tests
    # ─────────────────────────────────────────────────────────────

    test "git_config defaults username to rbrun" do
      assert_equal "rbrun", @config.git_config.username
    end

    test "git_config defaults email to sandbox@rbrun.dev" do
      assert_equal "sandbox@rbrun.dev", @config.git_config.email
    end

    test "#git yields and returns config" do
      @config.git do |g|
        g.pat = "github-token"
        g.repo = "owner/repo"
      end

      assert_equal "github-token", @config.git_config.pat
      assert_equal "owner/repo", @config.git_config.repo
    end

    # ─────────────────────────────────────────────────────────────
    # Claude Config Tests
    # ─────────────────────────────────────────────────────────────

    test "#claude yields and returns config" do
      @config.claude do |c|
        c.auth_token = "anthropic-key"
      end

      assert_equal "anthropic-key", @config.claude_config.auth_token
      assert_equal "https://api.anthropic.com", @config.claude_config.base_url
    end

    test "#claude_configured? returns false when not configured" do
      refute @config.claude_configured?
    end

    test "#claude_configured? returns true when auth_token present" do
      @config.claude { |c| c.auth_token = "key" }
      assert @config.claude_configured?
    end

    # ─────────────────────────────────────────────────────────────
    # Setup and Env Tests
    # ─────────────────────────────────────────────────────────────

    test "defaults setup_commands to empty array" do
      assert_equal [], @config.setup_commands
    end

    test "defaults env_vars to empty hash" do
      assert_equal({}, @config.env_vars)
    end

    test "#setup collects commands" do
      @config.setup("bundle install", "rails db:prepare", "custom command")

      assert_equal ["bundle install", "rails db:prepare", "custom command"], @config.setup_commands
    end

    test "#env collects variables" do
      @config.env(DATABASE_URL: "postgres://localhost/app", RAILS_ENV: "development")

      assert_equal "postgres://localhost/app", @config.env_vars[:DATABASE_URL]
      assert_equal "development", @config.env_vars[:RAILS_ENV]
    end

    test "#env supports hash syntax for sandbox/release values" do
      @config.env(RAILS_ENV: { sandbox: "development", release: "production" })

      expected = { sandbox: "development", release: "production" }
      assert_equal expected, @config.env_vars[:RAILS_ENV]
    end

    # ─────────────────────────────────────────────────────────────
    # Validation Tests
    # ─────────────────────────────────────────────────────────────

    test "#validate! raises if compute provider not configured" do
      @config.git_config.pat = "token"
      @config.git_config.repo = "repo"

      error = assert_raises(ConfigurationError) { @config.validate! }
      assert_match(/Compute provider not configured/, error.message)
    end

    test "#validate! raises if compute.api_key blank" do
      @config.compute(:hetzner)
      @config.git_config.pat = "token"
      @config.git_config.repo = "repo"

      error = assert_raises(ConfigurationError) { @config.validate! }
      assert_match(/compute\.api_key is required for Hetzner/, error.message)
    end

    test "#validate! raises if git.pat blank" do
      @config.compute(:hetzner) { |c| c.api_key = "key" }
      @config.git_config.repo = "repo"

      error = assert_raises(ConfigurationError) { @config.validate! }
      assert_match(/git\.pat is required/, error.message)
    end

    test "#validate! raises if git.repo blank" do
      @config.compute(:hetzner) { |c| c.api_key = "key" }
      @config.git_config.pat = "token"

      error = assert_raises(ConfigurationError) { @config.validate! }
      assert_match(/git\.repo is required/, error.message)
    end

    test "#validate! passes with minimal valid config" do
      @config.compute(:hetzner) { |c| c.api_key = "key" }
      @config.git_config.pat = "token"
      @config.git_config.repo = "repo"

      assert_nothing_raised { @config.validate! }
    end

    # ─────────────────────────────────────────────────────────────
    # Full Configuration Tests
    # ─────────────────────────────────────────────────────────────

    test "allows setting all config options via nested blocks" do
      @config.compute(:hetzner) do |c|
        c.api_key = "hetzner"
        c.server_type = { sandbox: "cx22", release: "cx32" }
        c.location = "nbg1"
      end

      @config.database(:postgres) do |db|
        db.volume_size = { sandbox: "10Gi", release: "50Gi" }
      end

      @config.database(:redis)

      @config.service(:meilisearch) do |s|
        s.subdomain = "search"
      end

      @config.app do |a|
        a.process(:web) do |p|
          p.command = "bin/rails server"
          p.port = 3000
          p.replicas = { sandbox: 1, release: 2 }
        end
        a.process(:worker) { |p| p.command = "bin/jobs" }
      end

      @config.storage { |s| s.subdomain = "assets" }

      @config.git do |g|
        g.pat = "github"
        g.repo = "owner/repo"
      end

      @config.cloudflare do |cf|
        cf.api_token = "cloudflare"
        cf.account_id = "account"
        cf.domain = "zone.dev"
      end

      @config.claude { |c| c.auth_token = "anthropic" }

      @config.setup("bundle install", "rails db:prepare")
      @config.env(RAILS_ENV: { sandbox: "development", release: "production" })

      # Verify compute
      assert_equal "hetzner", @config.compute_config.api_key
      assert_equal({ sandbox: "cx22", release: "cx32" }, @config.compute_config.server_type)

      # Verify databases
      assert @config.database?(:postgres)
      assert @config.database?(:redis)
      assert_equal({ sandbox: "10Gi", release: "50Gi" }, @config.database_configs[:postgres].volume_size)

      # Verify services
      assert @config.service?(:meilisearch)
      assert_equal "search", @config.service_configs[:meilisearch].subdomain

      # Verify app
      assert_equal 2, @config.app_config.processes.size
      assert_equal({ sandbox: 1, release: 2 }, @config.app_config.processes[:web].replicas)

      # Verify storage
      assert_equal "assets", @config.storage_config.subdomain

      # Verify git/cloudflare/claude
      assert_equal "github", @config.git_config.pat
      assert_equal "cloudflare", @config.cloudflare_config.api_token
      assert_equal "anthropic", @config.claude_config.auth_token

      # Verify setup/env
      assert_equal ["bundle install", "rails db:prepare"], @config.setup_commands
      assert_equal({ sandbox: "development", release: "production" }, @config.env_vars[:RAILS_ENV])
    end
  end
end
