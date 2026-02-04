# frozen_string_literal: true

require "yaml"
require "base64"

module Rbrun
  module Generators
    # Generates K3s manifests from unified configuration.
    # Single entry point: generate() returns all manifests as YAML string.
    class K3s
      NAMESPACE = "default"

      def initialize(config, prefix:, zone:, target:, db_password: nil, registry_tag: nil, tunnel_token: nil)
        @config = config
        @prefix = prefix
        @zone = zone
        @target = target
        @db_password = db_password || SecureRandom.hex(16)
        @registry_tag = registry_tag
        @tunnel_token = tunnel_token
      end

      def generate
        manifests = []

        manifests << app_secret
        manifests.concat(database_manifests) if @config.database?
        manifests.concat(service_manifests) if @config.service?
        manifests.concat(app_manifests) if @config.app? && @registry_tag
        manifests << tunnel_manifest if @tunnel_token

        to_yaml(manifests)
      end

      private

        def to_yaml(resources)
          Array(resources).compact.map { |r| YAML.dump(r.deep_stringify_keys) }.join("\n---\n")
        end

        # ─────────────────────────────────────────────────────────────
        # App Secret (env vars)
        # ─────────────────────────────────────────────────────────────

        def app_secret
          env_data = {}

          @config.env_vars.each do |key, value|
            env_data[key.to_s] = resolve(value).to_s
          end

          if @config.database?(:postgres)
            env_data["DATABASE_URL"] = "postgresql://app:#{@db_password}@#{@prefix}-postgres:5432/app"
            env_data["POSTGRES_HOST"] = "#{@prefix}-postgres"
            env_data["POSTGRES_USER"] = "app"
            env_data["POSTGRES_PASSWORD"] = @db_password
            env_data["POSTGRES_DB"] = "app"
            env_data["POSTGRES_PORT"] = "5432"
          end


          # Auto-inject service URLs for all configured services
          @config.service_configs.each do |name, svc_config|
            next unless svc_config.port
            env_var = "#{name.to_s.upcase}_URL"
            protocol = name == :redis ? "redis" : "http"
            env_data[env_var] = "#{protocol}://#{@prefix}-#{name}:#{svc_config.port}"
          end

          secret(name: "#{@prefix}-app-secret", data: env_data)
        end

        # ─────────────────────────────────────────────────────────────
        # Database Manifests
        # ─────────────────────────────────────────────────────────────

        def database_manifests
          manifests = []

          @config.database_configs.each do |type, db_config|
            case type
            when :postgres
              manifests.concat(postgres_manifests(db_config))
            when :redis
              manifests.concat(redis_manifests(db_config))
            end
          end

          manifests
        end

        def postgres_manifests(db_config)
          name = "#{@prefix}-postgres"
          secret_name = "#{name}-secret"

          [
            secret(name: secret_name, data: { "DB_PASSWORD" => @db_password }),
            deployment(
              name:,
              replicas: 1,
              containers: [{
                name: "postgres",
                image: db_config.image,
                ports: [{ containerPort: 5432 }],
                env: [
                  { name: "POSTGRES_USER", value: "app" },
                  { name: "POSTGRES_DB", value: "app" },
                  { name: "POSTGRES_PASSWORD", valueFrom: { secretKeyRef: { name: secret_name, key: "DB_PASSWORD" } } },
                  { name: "PGDATA", value: "/var/lib/postgresql/data/pgdata" }
                ],
                volumeMounts: [{ name: "data", mountPath: "/var/lib/postgresql/data" }],
                readinessProbe: { exec: { command: ["pg_isready", "-U", "app"] }, initialDelaySeconds: 5, periodSeconds: 5 }
              }],
              volumes: [host_path_volume("data", "/mnt/data/#{name}")]
            ),
            service(name:, port: 5432)
          ]
        end

        def redis_manifests(db_config)
          name = "#{@prefix}-redis"

          [
            deployment(
              name:,
              replicas: 1,
              containers: [{
                name: "redis",
                image: db_config.image,
                ports: [{ containerPort: 6379 }],
                volumeMounts: [{ name: "data", mountPath: "/data" }]
              }],
              volumes: [host_path_volume("data", "/mnt/data/#{name}")]
            ),
            service(name:, port: 6379)
          ]
        end

        # ─────────────────────────────────────────────────────────────
        # Service Manifests (meilisearch, etc.)
        # ─────────────────────────────────────────────────────────────

        def service_manifests
          manifests = []

          @config.service_configs.each do |name, svc_config|
            next if name == :redis && @config.database?(:redis)
            manifests.concat(generic_service_manifests(name, svc_config))
          end

          manifests
        end

        def generic_service_manifests(name, svc_config)
          deployment_name = "#{@prefix}-#{name}"
          secret_name = "#{deployment_name}-secret"
          manifests = []

          # Create per-service secret if env vars defined
          if svc_config.env.any?
            manifests << secret(name: secret_name, data: svc_config.env.transform_keys(&:to_s))
          end

          container = {
            name: name.to_s,
            image: svc_config.image,
            ports: svc_config.port ? [{ containerPort: svc_config.port }] : []
          }

          # Reference service's own secret for env vars
          if svc_config.env.any?
            container[:envFrom] = [{ secretRef: { name: secret_name } }]
          end

          manifests << deployment(
            name: deployment_name,
            replicas: 1,
            containers: [container.compact]
          )

          if svc_config.port
            manifests << service(name: deployment_name, port: svc_config.port)
          end

          subdomain = resolve(svc_config.subdomain)
          if subdomain && svc_config.port
            manifests << ingress(name: deployment_name, hostname: "#{subdomain}.#{@zone}", port: svc_config.port)
          end

          manifests
        end

        # ─────────────────────────────────────────────────────────────
        # App Manifests
        # ─────────────────────────────────────────────────────────────

        def app_manifests
          manifests = []

          @config.app_config.processes.each do |name, process|
            manifests.concat(process_manifests(name, process))
          end

          manifests
        end

        def process_manifests(name, process)
          deployment_name = "#{@prefix}-#{name}"
          replicas = resolve(process.replicas) || 1
          subdomain = resolve(process.subdomain)
          manifests = []

          container = {
            name: name.to_s,
            image: @registry_tag,
            envFrom: [{ secretRef: { name: "#{@prefix}-app-secret" } }]
          }

          container[:command] = ["/bin/sh", "-c", process.command] if process.command
          container[:ports] = [{ containerPort: process.port }] if process.port

          if process.port
            http_get = { path: "/", port: process.port }
            http_get[:httpHeaders] = [{ name: "Host", value: "#{subdomain}.#{@zone}" }] if subdomain && @zone
            container[:readinessProbe] = {
              httpGet: http_get,
              initialDelaySeconds: 10,
              periodSeconds: 10
            }
          end

          manifests << deployment(name: deployment_name, replicas:, containers: [container])

          if process.port
            manifests << service(name: deployment_name, port: process.port)
          end

          if subdomain && process.port
            manifests << ingress(name: deployment_name, hostname: "#{subdomain}.#{@zone}", port: process.port)
          end

          manifests
        end

        # ─────────────────────────────────────────────────────────────
        # Tunnel Manifest
        # ─────────────────────────────────────────────────────────────

        def tunnel_manifest
          name = "#{@prefix}-cloudflared"

          deployment(
            name:,
            replicas: 1,
            host_network: true,
            containers: [{
              name: "cloudflared",
              image: "cloudflare/cloudflared:latest",
              args: ["tunnel", "--no-autoupdate", "run", "--token", @tunnel_token]
            }]
          )
        end

        # ─────────────────────────────────────────────────────────────
        # Value Resolution
        # ─────────────────────────────────────────────────────────────

        def resolve(value)
          @config.resolve(value, target: @target)
        end

        # ─────────────────────────────────────────────────────────────
        # K8s Resource Builders
        # ─────────────────────────────────────────────────────────────

        def labels(name)
          {
            "app.kubernetes.io/name" => name,
            "app.kubernetes.io/instance" => @prefix,
            "app.kubernetes.io/managed-by" => "rbrun"
          }
        end

        def deployment(name:, containers:, volumes: [], replicas: 1, host_network: false)
          spec = { containers: }
          spec[:volumes] = volumes if volumes.any?
          spec[:hostNetwork] = true if host_network

          {
            apiVersion: "apps/v1",
            kind: "Deployment",
            metadata: { name:, namespace: NAMESPACE, labels: labels(name) },
            spec: {
              replicas:,
              selector: { matchLabels: { "app.kubernetes.io/name" => name } },
              template: {
                metadata: { labels: labels(name) },
                spec:
              }
            }
          }
        end

        def service(name:, port:)
          {
            apiVersion: "v1",
            kind: "Service",
            metadata: { name:, namespace: NAMESPACE, labels: labels(name) },
            spec: {
              selector: { "app.kubernetes.io/name" => name },
              ports: [{ port:, targetPort: port }]
            }
          }
        end

        def secret(name:, data:)
          {
            apiVersion: "v1",
            kind: "Secret",
            metadata: { name:, namespace: NAMESPACE },
            type: "Opaque",
            data: data.transform_values { |v| Base64.strict_encode64(v.to_s) }
          }
        end

        def ingress(name:, hostname:, port:)
          {
            apiVersion: "networking.k8s.io/v1",
            kind: "Ingress",
            metadata: {
              name:,
              namespace: NAMESPACE,
              annotations: { "nginx.ingress.kubernetes.io/proxy-body-size" => "50m" }
            },
            spec: {
              ingressClassName: "nginx",
              rules: [{
                host: hostname,
                http: {
                  paths: [{
                    path: "/",
                    pathType: "Prefix",
                    backend: { service: { name:, port: { number: port } } }
                  }]
                }
              }]
            }
          }
        end

        def host_path_volume(name, path)
          { name:, hostPath: { path:, type: "DirectoryOrCreate" } }
        end
    end
  end
end
