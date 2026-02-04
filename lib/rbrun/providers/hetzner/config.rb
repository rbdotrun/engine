# frozen_string_literal: true

module Rbrun
  module Providers
    module Hetzner
      class Config < Base
        attr_accessor :api_key, :server_type, :location, :image

        def initialize
          @server_type = "cpx11"
          @location = "ash"
          @image = "ubuntu-22.04"
        end

        def provider_name
          :hetzner
        end

        def supports_self_hosted?
          true
        end

        def validate!
          raise ConfigurationError, "compute.api_key is required for Hetzner" if api_key.blank?
        end

        def client
          @client ||= Client.new(api_key: @api_key)
        end
      end
    end
  end
end
