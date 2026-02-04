# frozen_string_literal: true

require "open3"

module Rbrun
  module Kubernetes
    # Builds and pushes Docker images to in-cluster registry.
    # Build runs locally via DOCKER_HOST=ssh:// to use remote Docker daemon.
    # Push goes to remote registry via the same SSH connection.
    class DockerBuilder
      REGISTRY_PORT = 30500
      KEEP_IMAGES = 3

      attr_reader :release, :prefix

      def initialize(release:, prefix:)
        @release = release
        @prefix = prefix
      end

      # Build image from local Dockerfile via SSH to remote Docker daemon
      def build!(context_path:, dockerfile: "Dockerfile", platform: "linux/amd64")
        ts = timestamp
        local = local_tag(ts)
        registry = registry_tag(ts)

        # Build via remote Docker daemon using DOCKER_HOST=ssh://
        run_docker!(
          "build",
          "--platform", platform,
          "--pull",
          "-f", dockerfile,
          "-t", local,
          ".",
          chdir: context_path,
          timeout: 600
        )

        # Tag for registry
        run_docker!("tag", local, registry)

        { local_tag: local, registry_tag: registry, timestamp: ts }
      end

      # Push image to in-cluster registry
      def push!(registry_tag)
        run_docker!("push", registry_tag, timeout: 300)
      end

      # Tag image as latest for build cache
      def tag_latest!(local_tag)
        latest = "#{prefix}:latest"
        run_docker!("tag", local_tag, latest)
      end

      # Cleanup old images, keeping most recent N
      def cleanup_old_images!(keep: KEEP_IMAGES)
        output = run_docker!(
          "images", prefix, "--format", "{{.Tag}} {{.ID}}",
          capture: true,
          raise_on_error: false
        )

        return if output.blank?

        output.each_line do |line|
          tag, _id = line.strip.split
          next if tag == "latest" || tag == "<none>"

          run_docker!("rmi", "#{prefix}:#{tag}", raise_on_error: false)
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

        # Run docker command locally but targeting remote daemon via SSH
        def run_docker!(*args, chdir: nil, timeout: 300, capture: false, raise_on_error: true)
          env = { "DOCKER_HOST" => docker_host }

          puts "        [docker] #{args.first} #{args[1..3].join(' ')}..."

          if capture
            output, status = Open3.capture2(env, "docker", *args, chdir: chdir)
            raise "docker #{args.first} failed" if raise_on_error && !status.success?
            output
          else
            success = system(env, "docker", *args, chdir: chdir)
            raise "docker #{args.first} failed" if raise_on_error && !success
            success
          end
        end

        def docker_host
          user = Rbrun::Naming.default_user
          ip = release.server&.public_ip
          raise "No server IP available for Docker build" unless ip
          "ssh://#{user}@#{ip}"
        end

        def run_ssh!(command, raise_on_error: true, timeout: 300)
          release.run_ssh!(command, raise_on_error:, timeout:)
        end
    end
  end
end
