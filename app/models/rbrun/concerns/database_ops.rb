# frozen_string_literal: true

module Rbrun
  module Concerns
    # Shared database operations for Sandbox (Docker Compose) and Release (K8s).
    # Host model must implement `container_exec(command:, container:)`.
    module DatabaseOps
      extend ActiveSupport::Concern

      # ─────────────────────────────────────────────────────────────
      # SQL Execution
      # ─────────────────────────────────────────────────────────────

      def sql(query, &block)
        raise "No database configured" unless database_configured?

        case database_type
        when :postgres
          psql(query, &block)
        when :mysql
          mysql_exec(query, &block)
        end
      end

      def psql(query, &block)
        escaped = query.gsub("'", "'\\''")
        container_exec(command: "psql $DATABASE_URL -c '#{escaped}'", container: :app, &block)
      end

      def mysql_exec(query, &block)
        escaped = query.gsub("'", "'\\''")
        cmd = "mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e '#{escaped}'"
        container_exec(command: cmd, container: :app, &block)
      end

      # ─────────────────────────────────────────────────────────────
      # Database Shell
      # ─────────────────────────────────────────────────────────────

      def db_shell(&block)
        case database_type
        when :postgres
          container_exec(command: "psql $DATABASE_URL", container: :app, &block)
        when :mysql
          cmd = "mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE"
          container_exec(command: cmd, container: :app, &block)
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Database Dump
      # ─────────────────────────────────────────────────────────────

      def db_dump(output_path: "/tmp/dump.sql", &block)
        case database_type
        when :postgres
          container_exec(command: "pg_dump $DATABASE_URL -f #{output_path}", container: :app, &block)
        when :mysql
          cmd = "mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE > #{output_path}"
          container_exec(command: cmd, container: :app, &block)
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Database Restore
      # ─────────────────────────────────────────────────────────────

      def db_restore(input_path: "/tmp/dump.sql", &block)
        case database_type
        when :postgres
          container_exec(command: "psql $DATABASE_URL -f #{input_path}", container: :app, &block)
        when :mysql
          cmd = "mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE < #{input_path}"
          container_exec(command: cmd, container: :app, &block)
        end
      end

      private

        def database_configured?
          Rbrun.configuration.database?
        end

        def database_type
          # First configured database type
          Rbrun.configuration.database_configs.keys.first || :postgres
        end
    end
  end
end
