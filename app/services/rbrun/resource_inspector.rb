# frozen_string_literal: true

module Rbrun
  # Lists all resources created on compute provider and Cloudflare.
  # Helps identify orphaned resources not tied to any sandbox.
  #
  # Usage:
  #   inspector = Rbrun::ResourceInspector.new
  #   inspector.all          # everything
  #   inspector.compute      # just compute provider
  #   inspector.cloudflare   # just cloudflare
  #   inspector.orphans      # resources without matching sandbox
  #
  class ResourceInspector
    def initialize
      @compute = Rbrun.configuration.compute_config&.client
      @cloudflare = Rbrun.configuration.cloudflare_config&.client
    end

    # All resources from both providers
    def all
      {
        compute:,
        cloudflare:
      }
    end

    # All compute provider resources
    def compute
      return {} unless @compute

      {
        servers: compute_servers,
        networks: compute_networks,
        firewalls: compute_firewalls
      }
    end

    # All Cloudflare resources
    def cloudflare
      return {} unless @cloudflare

      {
        tunnels: cloudflare_tunnels,
        dns_records: cloudflare_dns_records,
        workers: cloudflare_workers,
        worker_routes: cloudflare_worker_routes
      }
    end

    # Resources that don't have a matching sandbox in DB
    def orphans
      sandbox_slugs = Sandbox.pluck(:slug).to_set

      result = { compute: {}, cloudflare: {} }

      if @compute
        result[:compute] = {
          servers: compute_servers.reject { |s| sandbox_slugs.include?(extract_slug(s.name)) },
          networks: compute_networks.reject { |n| sandbox_slugs.include?(extract_slug(n.name)) },
          firewalls: compute_firewalls.reject { |f| sandbox_slugs.include?(extract_slug(f.name)) }
        }
      end

      if @cloudflare
        result[:cloudflare] = {
          tunnels: cloudflare_tunnels.reject { |t| sandbox_slugs.include?(extract_slug(t[:name])) },
          dns_records: cloudflare_dns_records.reject { |r| sandbox_slugs.include?(extract_slug(r[:name])) },
          workers: cloudflare_workers.reject { |w| sandbox_slugs.include?(extract_worker_slug(w[:id])) },
          worker_routes: cloudflare_worker_routes.reject { |r| sandbox_slugs.include?(extract_route_slug(r[:pattern])) }
        }
      end

      result
    end

    # Print summary to console
    def summary
      data = all

      if data[:compute].any?
        puts "=== COMPUTE (#{Rbrun.configuration.compute_config.provider_name}) ==="
        puts "Servers:   #{data[:compute][:servers]&.count || 0}"
        data[:compute][:servers]&.each { |s| puts "  - #{s.name} (#{s.status}) #{s.public_ipv4}" }

        puts "Networks:  #{data[:compute][:networks]&.count || 0}"
        data[:compute][:networks]&.each { |n| puts "  - #{n.name}" }

        puts "Firewalls: #{data[:compute][:firewalls]&.count || 0}"
        data[:compute][:firewalls]&.each { |f| puts "  - #{f.name}" }
      else
        puts "=== COMPUTE ==="
        puts "Not configured"
      end

      if data[:cloudflare].any?
        puts "\n=== CLOUDFLARE ==="
        puts "Tunnels:   #{data[:cloudflare][:tunnels]&.count || 0}"
        data[:cloudflare][:tunnels]&.each { |t| puts "  - #{t[:name]} (#{t[:status]})" }

        puts "DNS:       #{data[:cloudflare][:dns_records]&.count || 0}"
        data[:cloudflare][:dns_records]&.each { |r| puts "  - #{r[:name]} → #{r[:content]}" }

        puts "Workers:   #{data[:cloudflare][:workers]&.count || 0}"
        data[:cloudflare][:workers]&.each { |w| puts "  - #{w[:id]}" }

        puts "Routes:    #{data[:cloudflare][:worker_routes]&.count || 0}"
        data[:cloudflare][:worker_routes]&.each { |r| puts "  - #{r[:pattern]} → #{r[:script]}" }
      else
        puts "\n=== CLOUDFLARE ==="
        puts "Not configured"
      end

      nil
    end

    # Print orphans
    def orphan_summary
      data = orphans
      has_orphans = false

      puts "=== ORPHANED RESOURCES ==="

      if data[:compute][:servers]&.any?
        has_orphans = true
        puts "\nCompute Servers:"
        data[:compute][:servers].each { |s| puts "  - #{s.name} (#{s.id})" }
      end

      if data[:compute][:networks]&.any?
        has_orphans = true
        puts "\nCompute Networks:"
        data[:compute][:networks].each { |n| puts "  - #{n.name} (#{n.id})" }
      end

      if data[:compute][:firewalls]&.any?
        has_orphans = true
        puts "\nCompute Firewalls:"
        data[:compute][:firewalls].each { |f| puts "  - #{f.name} (#{f.id})" }
      end

      if data[:cloudflare][:tunnels]&.any?
        has_orphans = true
        puts "\nCloudflare Tunnels:"
        data[:cloudflare][:tunnels].each { |t| puts "  - #{t[:name]} (#{t[:id]})" }
      end

      if data[:cloudflare][:dns_records]&.any?
        has_orphans = true
        puts "\nCloudflare DNS:"
        data[:cloudflare][:dns_records].each { |r| puts "  - #{r[:name]} (#{r[:id]})" }
      end

      if data[:cloudflare][:workers]&.any?
        has_orphans = true
        puts "\nCloudflare Workers:"
        data[:cloudflare][:workers].each { |w| puts "  - #{w[:id]}" }
      end

      if data[:cloudflare][:worker_routes]&.any?
        has_orphans = true
        puts "\nCloudflare Routes:"
        data[:cloudflare][:worker_routes].each { |r| puts "  - #{r[:pattern]} (#{r[:id]})" }
      end

      puts "\nNo orphans found." unless has_orphans

      nil
    end

    private

      # --- Compute Provider ---

      def compute_servers
        @compute.list_servers.select { |s| Naming.resource_regex.match?(s.name) }
      end

      def compute_networks
        @compute.list_networks.select { |n| Naming.resource_regex.match?(n.name) }
      end

      def compute_firewalls
        @compute.list_firewalls.select { |f| Naming.resource_regex.match?(f.name) }
      end

      # --- Cloudflare ---

      def cloudflare_tunnels
        @cloudflare.list_tunnels.select { |t| Naming.resource_regex.match?(t[:name]) }
      end

      def cloudflare_dns_records
        domain = Rbrun.configuration.cloudflare_config.domain
        zone_id = @cloudflare.get_zone_id(domain) rescue nil
        return [] unless zone_id

        @cloudflare.list_dns_records(zone_id).select { |r| Naming.resource_regex.match?(r[:name]) }
      end

      def cloudflare_workers
        list_all_workers.select { |w| Naming.worker_regex.match?(w[:id]) }
      end

      def cloudflare_worker_routes
        domain = Rbrun.configuration.cloudflare_config.domain
        zone_id = @cloudflare.get_zone_id(domain) rescue nil
        return [] unless zone_id

        list_all_routes(zone_id).select { |r| Naming.resource_regex.match?(r[:pattern]) }
      end

      def list_all_workers
        response = @cloudflare.send(:get, "/accounts/#{@cloudflare.account_id}/workers/scripts")
        (response["result"] || []).map { |w| { id: w["id"], created_on: w["created_on"] } }
      end

      def list_all_routes(zone_id)
        response = @cloudflare.send(:get, "/zones/#{zone_id}/workers/routes")
        (response["result"] || []).map { |r| { id: r["id"], pattern: r["pattern"], script: r["script"] } }
      end

      # --- Helpers ---

      def extract_slug(name)
        match = name&.match(Naming.resource_regex)
        match ? match[1] : nil
      end

      def extract_worker_slug(name)
        match = name&.match(Naming.worker_regex)
        match ? match[1] : nil
      end

      def extract_route_slug(pattern)
        match = pattern&.match(Naming.hostname_regex)
        match ? match[1] : nil
      end
  end
end
