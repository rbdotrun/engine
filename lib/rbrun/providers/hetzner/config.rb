# frozen_string_literal: true

module Rbrun
  module Providers
    module Hetzner
      class Config < Base
        attr_accessor :api_key, :server_type, :location, :image, :ssh_key_path

        def initialize
          @server_type = "cpx11"
          @location = "ash"
          @image = "ubuntu-22.04"
          @ssh_key_path = nil
        end

        def ssh_keys_configured?
          @ssh_key_path.present? && File.exist?(File.expand_path(@ssh_key_path))
        end

        def read_ssh_keys
          return nil unless ssh_keys_configured?

          private_key_path = File.expand_path(@ssh_key_path)
          public_key_path = "#{private_key_path}.pub"

          raise ConfigurationError, "SSH public key not found: #{public_key_path}" unless File.exist?(public_key_path)

          {
            private_key: File.read(private_key_path),
            public_key: File.read(public_key_path).strip
          }
        end

        def provider_name
          :hetzner
        end

        def supports_self_hosted?
          true
        end

        def validate!
          raise ConfigurationError, "compute.api_key is required for Hetzner" if api_key.blank?
          raise ConfigurationError, "compute.ssh_key_path is required" if ssh_key_path.blank?
          raise ConfigurationError, "SSH private key not found: #{ssh_key_path}" unless File.exist?(File.expand_path(ssh_key_path))
          raise ConfigurationError, "SSH public key not found: #{ssh_key_path}.pub" unless File.exist?(File.expand_path("#{ssh_key_path}.pub"))
        end

        def ssh_private_key
          File.read(File.expand_path(ssh_key_path))
        end

        def ssh_public_key
          File.read(File.expand_path("#{ssh_key_path}.pub")).strip
        end

        def client
          @client ||= Client.new(api_key: @api_key)
        end
      end
    end
  end
end
