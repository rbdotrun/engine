# frozen_string_literal: true

module Rbrun
  # Single source of truth for all naming conventions.
  # All methods that accept a slug validate format and raise ArgumentError if invalid.
  # Slugs are 6 lowercase hex characters (e.g., "a1b2c3").
  module Naming
    PREFIX = "rbrun-sandbox"
    SLUG_LENGTH = 6
    SLUG_REGEX = /\A[a-f0-9]{#{SLUG_LENGTH}}\z/

    class << self
      # Generate a new slug for sandbox identification.
      # Caller: Sandbox model before_validation callback.
      # Output: 6 lowercase hex characters (e.g., "a1b2c3").
      def generate_slug
        SecureRandom.hex(SLUG_LENGTH / 2)
      end

      # Check if slug matches expected format.
      # Caller: validate_slug!, model validations.
      # Output: true if valid 6-char hex string, false otherwise.
      def valid_slug?(slug)
        SLUG_REGEX.match?(slug.to_s)
      end

      # Validate slug format, raise if invalid.
      # Caller: All naming methods that accept a slug.
      # Raises: ArgumentError with descriptive message.
      def validate_slug!(slug)
        return if valid_slug?(slug)
        raise ArgumentError, "Invalid slug format: #{slug.inspect}. Expected #{SLUG_LENGTH} hex chars."
      end

      # Default SSH user for VM provisioning.
      # Caller: Ssh::Client, Providers::CloudInit.
      # Output: "deploy" (hardcoded - no root access).
      def default_user
        "deploy"
      end

      # Cookie name for preview authentication.
      # Caller: Cloudflare::Worker script generation.
      # Used to persist auth token across preview requests.
      def auth_cookie
        "#{PREFIX}-auth"
      end

      # Infrastructure resource name (servers, firewalls, networks, tunnels).
      # Caller: Provisionable, Previewable, ResourceInspector.
      # Used for: Hetzner resources, Cloudflare tunnel names.
      def resource(slug)
        validate_slug!(slug)
        "#{PREFIX}-#{slug}"
      end

      # Release K8s resource prefix for deployments, services, etc.
      # Caller: Release provisioner, Generators::K3s.
      # Format: appname-environment (e.g., "myapp-staging", "myapp-production")
      def release_prefix(app_name, environment)
        "#{app_name}-#{environment}"
      end

      # Regex to extract slug from resource name.
      # Caller: ResourceInspector for orphan detection.
      # Captures slug in match group 1.
      def resource_regex
        /^#{PREFIX}-([a-f0-9]{#{SLUG_LENGTH}})/
      end

      # Container name with role suffix.
      # Caller: Sandbox#app_container, Previewable for tunnel container.
      # Roles: "app", "tunnel", "db", etc.
      def container(slug, role)
        validate_slug!(slug)
        "#{PREFIX}-#{slug}-#{role}"
      end

      # Git branch name for sandbox isolation.
      # Caller: Provisionable during repo checkout.
      # Creates isolated branch for each sandbox's changes.
      def branch(slug)
        validate_slug!(slug)
        "#{PREFIX}/#{slug}"
      end

      # Preview hostname for Cloudflare tunnel DNS.
      # Caller: Previewable for DNS record creation.
      # Domain from cloudflare_config.domain.
      def hostname(slug, domain)
        validate_slug!(slug)
        "#{PREFIX}-#{slug}.#{domain}"
      end

      # Regex to extract slug from hostname.
      # Caller: ResourceInspector for worker route parsing.
      # Captures slug in match group 1.
      def hostname_regex
        /^#{PREFIX}-([a-f0-9]{#{SLUG_LENGTH}})\./
      end

      # Self-hosted preview URL via Cloudflare tunnel.
      # Caller: Previewable#preview_url.
      # Returns full HTTPS URL for authenticated preview access.
      def self_hosted_preview_url(slug, domain)
        validate_slug!(slug)
        "https://#{hostname(slug, domain)}"
      end

      # Cloudflare Worker name for widget injection.
      # Caller: Cloudflare::Client#worker_name, #deploy_worker.
      # Worker handles auth cookies and injects console widget.
      def worker(slug)
        validate_slug!(slug)
        "#{PREFIX}-widget-#{slug}"
      end

      # Regex to extract slug from worker name.
      # Caller: ResourceInspector for orphan detection.
      # Captures slug in match group 1.
      def worker_regex
        /^#{PREFIX}-widget-([a-f0-9]{#{SLUG_LENGTH}})/
      end

      # Worker route pattern for Cloudflare.
      # Caller: Cloudflare::Client#create_worker_route.
      # Matches all paths under the preview hostname.
      def worker_route(slug, domain)
        validate_slug!(slug)
        "#{hostname(slug, domain)}/*"
      end

      # SSH key comment for identification.
      def ssh_comment(slug)
        validate_slug!(slug)
        "#{PREFIX}-#{slug}"
      end
    end
  end
end
