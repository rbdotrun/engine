# frozen_string_literal: true

module Rbrun
  module Generators
    # Generates docker-compose.yml from unified configuration for sandbox environments.
    class Compose
      def initialize(config)
        @config = config
      end

      def generate
        {
          "services" => generate_services,
          "volumes" => generate_volumes
        }.compact.to_yaml
      end

      private

        def generate_services
          services = {}

          # App processes
          @config.app_config&.processes&.each do |name, process|
            services[name.to_s] = app_service(name, process)
          end

          # Databases
          @config.database_configs.each do |type, db_config|
            services[type.to_s] = database_service(type, db_config)
          end

          # Services (redis, meilisearch, etc.)
          @config.service_configs.each do |name, service_config|
            services[name.to_s] = service_service(name, service_config)
          end

          services
        end

        def app_service(name, process)
          service = {
            "build" => ".",
            "volumes" => [".:/app"],
            "environment" => resolved_env_vars
          }

          if process.command
            service["command"] = process.command
          end

          if process.port
            service["ports"] = ["#{process.port}:#{process.port}"]
          end

          # Add depends_on for databases and services
          depends = []
          depends += @config.database_configs.keys.map(&:to_s)
          depends += @config.service_configs.keys.map(&:to_s)
          service["depends_on"] = depends if depends.any?

          service
        end

        def database_service(type, db_config)
          case type
          when :postgres
            postgres_service(db_config)
          when :redis
            redis_service(db_config)
          when :sqlite
            nil # SQLite is file-based, no service needed
          end
        end

        def postgres_service(db_config)
          {
            "image" => db_config.image,
            "volumes" => ["postgres_data:/var/lib/postgresql/data"],
            "environment" => {
              "POSTGRES_USER" => "app",
              "POSTGRES_PASSWORD" => "app",
              "POSTGRES_DB" => "app_development"
            }
          }
        end

        def redis_service(db_config)
          {
            "image" => db_config.image,
            "volumes" => ["redis_data:/data"]
          }
        end

        def service_service(name, service_config)
          service = {
            "image" => service_config.image
          }

          if service_config.port
            service["ports"] = ["#{service_config.port}:#{service_config.port}"]
          end

          # Add volume for services that need persistence
          case name
          when :redis
            service["volumes"] = ["#{name}_data:/data"]
          when :meilisearch
            service["volumes"] = ["#{name}_data:/meili_data"]
          end

          service
        end

        def generate_volumes
          volumes = {}

          @config.database_configs.each do |type, _|
            case type
            when :postgres
              volumes["postgres_data"] = nil
            when :redis
              volumes["redis_data"] = nil
            end
          end

          @config.service_configs.each do |name, _|
            volumes["#{name}_data"] = nil
          end

          volumes.any? ? volumes : nil
        end

        def resolved_env_vars
          env = {}

          @config.env_vars.each do |key, value|
            env[key.to_s] = @config.resolve(value, target: :sandbox)
          end

          # Add database URLs
          if @config.database?(:postgres)
            env["DATABASE_URL"] = "postgres://app:app@postgres:5432/app_development"
          end

          if @config.database?(:redis) || @config.service?(:redis)
            env["REDIS_URL"] = "redis://redis:6379"
          end

          # Bind to all interfaces for Docker
          env["BINDING"] = "0.0.0.0"

          env
        end
    end
  end
end
