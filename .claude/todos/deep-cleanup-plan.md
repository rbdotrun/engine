# Deep Cleanup Plan: Self-Hosted Only

## Objective

Remove all managed service providers (Neon, Turso, Daytona, Upstash) and focus 100% on self-hosting. Implement unified DSL that generates both Compose (sandbox) and K3s (release) from same config.

---

## Phase 1: Delete Managed Providers

### 1.1 Remove Turso (Managed SQLite)

**Delete files:**
```
lib/rbrun/databases/sql/turso/client.rb
lib/rbrun/databases/sql/turso/config.rb
lib/rbrun/databases/sql/turso/           (directory)
```

**Remove requires from `lib/rbrun.rb`:**
```ruby
# DELETE lines 40-42:
require "rbrun/databases/sql/turso/client"
require "rbrun/databases/sql/turso/config"
```

**Update `lib/rbrun/databases/registry.rb`:**
```ruby
# Remove :turso from SQL_PROVIDERS hash
```

---

### 1.2 Remove Neon (Managed Postgres)

**Delete files:**
```
lib/rbrun/databases/sql/neon/client.rb
lib/rbrun/databases/sql/neon/config.rb
lib/rbrun/databases/sql/neon/            (directory)
```

**Remove requires from `lib/rbrun.rb`:**
```ruby
# DELETE lines 36-38:
require "rbrun/databases/sql/neon/client"
require "rbrun/databases/sql/neon/config"
```

**Update `lib/rbrun/databases/registry.rb`:**
```ruby
# Remove :neon from SQL_PROVIDERS hash
```

**Update `lib/rbrun/provisioners/base.rb`:**
```ruby
# Remove neon_configured?() method
# Remove cleanup_database!() method (or refactor for self-hosted only)
```

---

### 1.3 Remove Daytona (Container Compute)

**Delete files:**
```
lib/rbrun/providers/daytona/client.rb
lib/rbrun/providers/daytona/config.rb
lib/rbrun/providers/daytona/             (directory)
lib/rbrun/provisioners/container.rb      (entire file)
```

**Remove requires from `lib/rbrun.rb`:**
```ruby
# DELETE lines 22-23:
require "rbrun/providers/daytona/config"
require "rbrun/providers/daytona/client"
```

**Update `lib/rbrun/providers/registry.rb`:**
```ruby
# Remove :daytona from PROVIDERS hash
```

**Update `lib/rbrun/provisioners.rb`:**
```ruby
# Remove daytona => Container mapping from CATALOG
```

**Update `app/models/rbrun/sandbox/provisionable.rb`:**
```ruby
# Remove run_daytona!() method
# Remove daytona_preview_url() method
# Remove daytona_sandbox() method
```

**Update `app/models/rbrun/claude_session/runnable.rb`:**
```ruby
# Remove run_remote_daytona() method
```

---

### 1.4 Remove Upstash (Managed Redis)

**Delete files:**
```
lib/rbrun/databases/kv/upstash/client.rb
lib/rbrun/databases/kv/upstash/config.rb
lib/rbrun/databases/kv/upstash/          (directory)
```

**Remove requires from `lib/rbrun.rb`:**
```ruby
# DELETE lines 46-47:
require "rbrun/databases/kv/upstash/client"
require "rbrun/databases/kv/upstash/config"
```

**Update `lib/rbrun/databases/registry.rb`:**
```ruby
# Remove :upstash from KV_PROVIDERS hash
```

---

## Phase 2: Clean Up Tests

### Delete test files:
```
test/lib/rbrun/provisioners/container_test.rb  (entire file)
```

### Update test files (remove managed provider tests):
```
test/lib/rbrun/configuration_test.rb
  - Remove Neon configuration tests
  - Remove Turso configuration tests
  - Remove Daytona configuration tests
  - Remove Upstash configuration tests

test/lib/rbrun/provisioners/base_test.rb
  - Remove neon_configured? tests
  - Remove cleanup_database! tests for Neon

test/lib/rbrun/configuration/sandbox_config_test.rb
  - Remove managed database tests

test/models/rbrun/sandbox/provisionable_test.rb
  - Remove Daytona provisioning tests
```

---

## Phase 3: Clean Up Rake Tasks

**File: `lib/tasks/rbrun_tasks.rake`**

### Remove smoke tests:
```ruby
# Remove smoke_test:hetzner_neon task
# Remove smoke_test:daytona_neon task
# Remove from smoke_test:all matrix
```

### Remove configuration methods:
```ruby
# Remove configure_hetzner_neon!()
# Remove configure_daytona_neon!()
```

### Keep only:
```ruby
smoke_test:hetzner_self_hosted
```

---

## Phase 4: Simplify Configuration

### Update `lib/rbrun/configuration.rb`:

Remove error messages referencing managed providers:
```ruby
# Update validation messages to only mention self-hosted options
```

Remove provider-specific checks:
```ruby
# Remove daytona_configured? references
# Remove neon_configured? references
```

---

## Phase 5: Unified DSL Refactor

### New Configuration Structure

**Delete:**
```
lib/rbrun/configuration/sandbox_config.rb   (current version)
lib/rbrun/configuration/release_config.rb   (current version)
```

**Create unified config: `lib/rbrun/configuration/app_config.rb`**

```ruby
module Rbrun
  class AppConfig
    attr_reader :database_config, :services, :processes, :storage_config

    def database(type, &block)
      # Only :postgres or :sqlite
      @database_config = DatabaseConfig.new(type)
      block.call(@database_config) if block
    end

    def service(name, &block)
      @services[name] = ServiceConfig.new(name)
      block.call(@services[name]) if block
    end

    def app(&block)
      @app_config = ProcessConfig.new
      block.call(@app_config) if block
    end

    def storage(&block)
      @storage_config = StorageConfig.new
      block.call(@storage_config) if block
    end
  end

  class DatabaseConfig
    attr_accessor :version, :volume_size, :backup_schedule, :backup_retention

    def initialize(type)
      @type = type  # :postgres or :sqlite
    end

    # Unified interface (works for both compose and k3s)
    def volume_size=(value)
      @volume_size = resolve_env_value(value)  # handles { sandbox: 10, release: 50 }
    end

    def backup(schedule:, retention: 30)
      @backup_schedule = schedule
      @backup_retention = retention
    end
  end

  class ServiceConfig
    attr_accessor :image, :volume_size, :port, :subdomain, :env
  end

  class ProcessConfig
    attr_accessor :dockerfile, :platform, :env
    attr_reader :processes

    def web(&block)
      @processes[:web] = WebProcess.new
      block.call(@processes[:web]) if block
    end

    def worker(name, &block)
      @processes[name] = WorkerProcess.new(name)
      block.call(@processes[name]) if block
    end

    def cron(name, &block)
      @processes[name] = CronProcess.new(name)
      block.call(@processes[name]) if block
    end
  end

  class WebProcess
    attr_accessor :command, :port, :subdomain, :instances, :memory, :cpu
  end

  class WorkerProcess
    attr_accessor :command, :instances, :memory, :cpu
  end

  class CronProcess
    attr_accessor :command, :schedule
  end

  class StorageConfig
    attr_accessor :subdomain
    # bucket name inferred from naming
  end
end
```

### Environment-Aware Value Resolution

```ruby
module Rbrun
  module EnvValue
    def resolve_env_value(value, context:)
      return value unless value.is_a?(Hash)
      value[context] || value[:default] || value.values.first
    end
  end
end
```

Usage:
```ruby
h.server_type = { sandbox: "cx22", release: "cx32" }
db.volume_size = { sandbox: 10, release: 50 }
w.instances = { sandbox: 1, release: 2 }
```

---

## Phase 6: Dual Output Generators

### Compose Generator (Sandbox)

**Create: `lib/rbrun/generators/compose_generator.rb`**

Generates `docker-compose.yml` from unified config:
- App processes → containers
- Database → postgres/sqlite container with volume
- Services → containers with volumes
- Mounts workspace for Claude Code

### K3s Generator (Release)

Already exists in `lib/rbrun/release/kubernetes/manifests/`

Update to use unified config instead of ReleaseConfig.

---

## Phase 7: Unified Database Interface

### Refactor: `lib/rbrun/databases/`

```ruby
module Rbrun
  module Database
    class Base
      def execute(sql); raise NotImplementedError; end
      def shell; raise NotImplementedError; end
      def dump(path); raise NotImplementedError; end
      def restore(path); raise NotImplementedError; end
      def connection_url; raise NotImplementedError; end
    end

    class Postgres < Base
      def initialize(context:, ssh_client:)
        @context = context  # :sandbox or :release
        @ssh_client = ssh_client
      end

      def execute(sql)
        case @context
        when :sandbox
          # docker exec -i postgres psql ...
        when :release
          # kubectl exec -i postgres-pod -- psql ...
        end
      end

      def shell
        # Similar context-aware execution
      end

      def dump(path)
        # pg_dump via docker exec or kubectl exec
      end

      def restore(path)
        # pg_restore via docker exec or kubectl exec
      end

      def connection_url
        # Returns DATABASE_URL for app container
      end
    end
  end
end
```

---

## Final Directory Structure

```
lib/rbrun/
├── databases/
│   ├── base.rb
│   ├── postgres.rb          # Unified (compose + k3s)
│   ├── sqlite.rb            # Unified
│   └── redis.rb             # Unified
├── providers/
│   ├── hetzner/             # Keep
│   └── scaleway/            # Keep
├── provisioners/
│   ├── base.rb              # Cleaned up
│   └── vm.rb                # Keep
├── generators/
│   └── compose_generator.rb # New
├── release/
│   └── kubernetes/          # Keep (K3s manifests)
└── configuration/
    ├── app_config.rb        # New unified config
    ├── git_config.rb        # Keep
    └── claude_config.rb     # Keep
```

---

## Execution Order

1. **Phase 1**: Delete managed provider files (Turso, Neon, Daytona, Upstash)
2. **Phase 2**: Clean up tests
3. **Phase 3**: Clean up rake tasks
4. **Phase 4**: Simplify configuration error messages
5. **Run tests**: Ensure nothing breaks
6. **Phase 5**: Implement unified DSL (new AppConfig)
7. **Phase 6**: Implement Compose generator
8. **Phase 7**: Refactor database interface
9. **Final tests**: Full coverage

---

## Files Summary

### DELETE (12 files + 4 directories):
```
lib/rbrun/databases/sql/turso/          (directory)
lib/rbrun/databases/sql/neon/           (directory)
lib/rbrun/databases/kv/upstash/         (directory)
lib/rbrun/providers/daytona/            (directory)
lib/rbrun/provisioners/container.rb
test/lib/rbrun/provisioners/container_test.rb
```

### MODIFY (15+ files):
```
lib/rbrun.rb
lib/rbrun/databases/registry.rb
lib/rbrun/providers/registry.rb
lib/rbrun/provisioners.rb
lib/rbrun/provisioners/base.rb
lib/rbrun/configuration.rb
app/models/rbrun/sandbox/provisionable.rb
app/models/rbrun/claude_session/runnable.rb
lib/tasks/rbrun_tasks.rake
test/lib/rbrun/configuration_test.rb
test/lib/rbrun/provisioners/base_test.rb
test/models/rbrun/sandbox/provisionable_test.rb
(+ more test files)
```

### CREATE (new):
```
lib/rbrun/configuration/app_config.rb
lib/rbrun/generators/compose_generator.rb
lib/rbrun/databases/postgres.rb (refactored)
lib/rbrun/databases/redis.rb (refactored)
```
