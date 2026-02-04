# frozen_string_literal: true

module Rbrun
  module Kubernetes
    # Resource management for K3s: profiles, priority classes, and auto-sizing.
    # Designed to protect databases while letting apps compete fairly for remaining resources.
    #
    # Philosophy (from k3s-fine-tune.md):
    # - CPU requests for scheduling weight, NO CPU limits (throttling is invisible pain)
    # - Memory limits for safety (OOM is visible, debuggable)
    # - Priority classes ensure database survives node pressure
    # - Kubelet evicts low-priority pods first
    module Resources
      # Priority class values - higher = harder to evict
      PRIORITIES = {
        database: 1_000_000_000,  # Max safe value - never evict
        platform: 100_000,        # Ingress, registry, cloudflared
        app: 1_000                # User workloads - evict first
      }.freeze

      # Resource profiles by workload type
      # Memory: request = guaranteed, limit = burst cap
      # CPU: request only (scheduling weight), no limit
      PROFILES = {
        # Database: generous allocation, protected
        database: {
          requests: { memory: "512Mi", cpu: "250m" },
          limits:   { memory: "1536Mi" }  # No CPU limit
        },

        # Platform services: minimal footprint
        platform: {
          requests: { memory: "64Mi", cpu: "50m" },
          limits:   { memory: "256Mi" }
        },

        # App processes by size
        small: {
          requests: { memory: "256Mi", cpu: "100m" },
          limits:   { memory: "512Mi" }
        },
        medium: {
          requests: { memory: "256Mi", cpu: "200m" },
          limits:   { memory: "512Mi" }
        },
        large: {
          requests: { memory: "512Mi", cpu: "300m" },
          limits:   { memory: "1Gi" }
        }
      }.freeze

      # Default size for app processes
      DEFAULT_APP_SIZE = :small

      class << self
        # Returns priority class manifests to deploy during K3s setup
        def priority_class_manifests
          [
            priority_class("database-critical", PRIORITIES[:database], "Database workloads - never evict"),
            priority_class("platform", PRIORITIES[:platform], "Platform services - evict after apps"),
            priority_class("app", PRIORITIES[:app], "Application workloads - evict first", global_default: true)
          ]
        end

        # Returns YAML string for kubectl apply
        def priority_class_yaml
          priority_class_manifests.map { |m| YAML.dump(m.deep_stringify_keys) }.join("\n---\n")
        end

        # Get resource spec for a container
        # type: :database, :platform, :small, :medium, :large
        def for(type)
          profile = PROFILES[type] || PROFILES[DEFAULT_APP_SIZE]
          deep_copy(profile)
        end

        # Get priority class name for a workload type
        # type: :database, :platform, :app
        def priority_class_for(type)
          case type
          when :database then "database-critical"
          when :platform then "platform"
          else "app"
          end
        end

        # Detect node memory and adjust profiles if needed (future use)
        # Returns adjusted profiles hash
        def auto_size_for_node(node_memory_bytes)
          node_gi = node_memory_bytes / (1024 ** 3)

          # 8GB node (our baseline) - use defaults
          return PROFILES.dup if node_gi <= 8

          # 16GB+ node - allow larger burst limits
          profiles = deep_copy(PROFILES)
          if node_gi >= 16
            profiles[:database][:limits][:memory] = "2Gi"
            profiles[:large][:limits][:memory] = "2Gi"
          end

          profiles
        end

        private

        def priority_class(name, value, description, global_default: false)
          {
            apiVersion: "scheduling.k8s.io/v1",
            kind: "PriorityClass",
            metadata: { name: name },
            value: value,
            globalDefault: global_default,
            preemptionPolicy: "PreemptLowerPriority",
            description: description
          }
        end

        def deep_copy(hash)
          Marshal.load(Marshal.dump(hash))
        end
      end
    end
  end
end
