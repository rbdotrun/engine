# frozen_string_literal: true

module Rbrun
  module Providers
    class Registry
      PROVIDERS = {
        hetzner: "Rbrun::Providers::Hetzner::Config",
        scaleway: "Rbrun::Providers::Scaleway::Config"
      }.freeze

      def self.build(provider, &block)
        klass_name = PROVIDERS[provider]
        raise ArgumentError, "Unknown compute provider: #{provider}" unless klass_name

        klass = klass_name.constantize
        config = klass.new
        yield config if block_given?
        config
      end
    end
  end
end
