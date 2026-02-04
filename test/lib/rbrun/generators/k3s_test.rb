# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Generators
    class K3sTest < ActiveSupport::TestCase
      def setup
        super
        Rbrun.reset_configuration!
        @config = Rbrun.configuration
      end

      # ─────────────────────────────────────────────────────────────
      # Service URL Injection Tests
      # ─────────────────────────────────────────────────────────────

      test "generates MEILISEARCH_URL for meilisearch service" do
        @config.service(:meilisearch)

        generator = K3s.new(@config, target: :production, prefix: "test", zone: "example.com")
        manifests = generator.generate

        assert_includes manifests, "MEILISEARCH_URL"
        # Value is base64 encoded in secret
        assert_includes manifests, Base64.strict_encode64("http://test-meilisearch:7700")
      end

      test "generates REDIS_URL with redis protocol for redis service" do
        @config.service(:redis)

        generator = K3s.new(@config, target: :production, prefix: "test", zone: "example.com")
        manifests = generator.generate

        assert_includes manifests, "REDIS_URL"
        # Value is base64 encoded in secret
        assert_includes manifests, Base64.strict_encode64("redis://test-redis:6379")
      end

      test "generates URLs for multiple services" do
        @config.service(:redis)
        @config.service(:meilisearch)

        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com")
        manifests = generator.generate

        assert_includes manifests, "REDIS_URL"
        assert_includes manifests, Base64.strict_encode64("redis://myapp-redis:6379")
        assert_includes manifests, "MEILISEARCH_URL"
        assert_includes manifests, Base64.strict_encode64("http://myapp-meilisearch:7700")
      end

      # ─────────────────────────────────────────────────────────────
      # Per-Service Secret Tests
      # ─────────────────────────────────────────────────────────────

      test "creates per-service secret when env vars defined" do
        @config.service(:meilisearch) { |m| m.env = { MEILI_MASTER_KEY: "secret123" } }

        generator = K3s.new(@config, target: :production, prefix: "test", zone: "example.com")
        manifests = generator.generate

        assert_includes manifests, "test-meilisearch-secret"
        assert_includes manifests, "MEILI_MASTER_KEY"
      end

      test "does not create service secret when no env vars" do
        @config.service(:redis)

        generator = K3s.new(@config, target: :production, prefix: "test", zone: "example.com")
        manifests = generator.generate

        refute_includes manifests, "test-redis-secret"
      end

      test "service container references its own secret via envFrom" do
        @config.service(:meilisearch) { |m| m.env = { MEILI_MASTER_KEY: "key" } }

        generator = K3s.new(@config, target: :production, prefix: "test", zone: "example.com")
        manifests = generator.generate

        assert_includes manifests, "secretRef"
        assert_includes manifests, "test-meilisearch-secret"
      end

      # ─────────────────────────────────────────────────────────────
      # Database URL Tests
      # ─────────────────────────────────────────────────────────────

      test "generates DATABASE_URL for postgres database" do
        @config.database(:postgres)

        generator = K3s.new(@config, target: :production, prefix: "app", zone: "example.com", db_password: "testpw")
        manifests = generator.generate

        assert_includes manifests, "DATABASE_URL"
        # Value is base64 encoded in secret
        assert_includes manifests, Base64.strict_encode64("postgresql://app:testpw@app-postgres:5432/app")
      end

      test "generates individual POSTGRES_* env vars" do
        @config.database(:postgres)

        generator = K3s.new(@config, target: :production, prefix: "app", zone: "example.com", db_password: "pw")
        manifests = generator.generate

        assert_includes manifests, "POSTGRES_HOST"
        assert_includes manifests, "POSTGRES_USER"
        assert_includes manifests, "POSTGRES_PASSWORD"
        assert_includes manifests, "POSTGRES_DB"
        assert_includes manifests, "POSTGRES_PORT"
      end

      # ─────────────────────────────────────────────────────────────
      # App Process Tests
      # ─────────────────────────────────────────────────────────────

      test "generates deployment for app process with port" do
        @config.app do |a|
          a.process(:web) { |p| p.port = 3000 }
        end

        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com", registry_tag: "localhost:5000/app:v1")
        manifests = generator.generate

        assert_includes manifests, "myapp-web"
        assert_includes manifests, "containerPort: 3000"
      end

      test "generates deployment for worker process without port" do
        @config.app do |a|
          a.process(:worker) { |p| p.command = "bin/jobs" }
        end

        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com", registry_tag: "localhost:5000/app:v1")
        manifests = generator.generate

        assert_includes manifests, "myapp-worker"
        assert_includes manifests, "bin/jobs"
      end

      test "generates ingress for process with subdomain" do
        @config.app do |a|
          a.process(:web) do |p|
            p.port = 3000
            p.subdomain = "app"
          end
        end

        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com", registry_tag: "localhost:5000/app:v1")
        manifests = generator.generate

        assert_includes manifests, "kind: Ingress"
        assert_includes manifests, "host: app.example.com"
      end

      # ─────────────────────────────────────────────────────────────
      # Tunnel Tests
      # ─────────────────────────────────────────────────────────────

      test "generates cloudflared deployment when tunnel_token provided" do
        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com", tunnel_token: "cf-token-123")
        manifests = generator.generate

        assert_includes manifests, "myapp-cloudflared"
        assert_includes manifests, "cloudflare/cloudflared"
        assert_includes manifests, "cf-token-123"
      end

      test "cloudflared uses hostNetwork" do
        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com", tunnel_token: "token")
        manifests = generator.generate

        assert_includes manifests, "hostNetwork: true"
      end

      test "does not generate cloudflared without tunnel_token" do
        generator = K3s.new(@config, target: :production, prefix: "myapp", zone: "example.com")
        manifests = generator.generate

        refute_includes manifests, "cloudflared"
      end
    end
  end
end
