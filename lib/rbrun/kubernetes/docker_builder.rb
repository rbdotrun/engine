# frozen_string_literal: true

module Rbrun
  module Kubernetes
    # Builds and pushes Docker images to in-cluster registry.
    # All commands go through release.run_ssh! -> CommandExecution -> CommandLog.
    class DockerBuilder
      REGISTRY_PORT = 30500
      KEEP_IMAGES = 3

      attr_reader :release, :prefix

      def initialize(release:, prefix:)
        @release = release
        @prefix = prefix
      end

      # Build image from Dockerfile
      def build!(context_path:, dockerfile: "Dockerfile", platform: "linux/amd64")
        ts = timestamp
        local = local_tag(ts)
        registry = registry_tag(ts)

        # Build image
        run_ssh!(<<~BASH, timeout: 600)
          cd #{context_path} && \
          docker build \
            --platform #{platform} \
            --pull \
            -f #{dockerfile} \
            -t #{local} \
            .
        BASH

        # Tag for registry
        run_ssh!("docker tag #{local} #{registry}")

        { local_tag: local, registry_tag: registry, timestamp: ts }
      end

      # Push image to in-cluster registry
      def push!(registry_tag)
        run_ssh!("docker push #{registry_tag}", timeout: 300)
      end

      # Tag image as latest for build cache
      def tag_latest!(local_tag)
        latest = "#{prefix}:latest"
        run_ssh!("docker tag #{local_tag} #{latest}")
      end

      # Cleanup old images, keeping most recent N
      def cleanup_old_images!(keep: KEEP_IMAGES)
        exec = run_ssh!(
          "docker images #{prefix} --format '{{.Tag}} {{.ID}}' | grep -v latest | head -n -#{keep}",
          raise_on_error: false
        )

        return if exec.output.blank?

        exec.output.each_line do |line|
          tag, id = line.strip.split
          next if tag == "latest"

          run_ssh!("docker rmi #{prefix}:#{tag} 2>/dev/null || true", raise_on_error: false)
          run_ssh!("crictl rmi localhost:#{REGISTRY_PORT}/#{prefix}:#{tag} 2>/dev/null || true", raise_on_error: false)
        end
      end

      # Full build + push workflow
      def build_and_push!(context_path:, dockerfile: "Dockerfile", platform: "linux/amd64")
        result = build!(context_path:, dockerfile:, platform:)
        push!(result[:registry_tag])
        tag_latest!(result[:local_tag])
        cleanup_old_images!
        result
      end

      private

        def timestamp
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        end

        def local_tag(ts)
          "#{prefix}:#{ts}"
        end

        def registry_tag(ts)
          "localhost:#{REGISTRY_PORT}/#{prefix}:#{ts}"
        end

        def run_ssh!(command, raise_on_error: true, timeout: 300)
          release.run_ssh!(command, raise_on_error:, timeout:)
        end
    end
  end
end
