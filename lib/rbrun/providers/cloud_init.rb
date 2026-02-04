# frozen_string_literal: true

module Rbrun
  module Providers
    # Generates cloud-init YAML for VM provisioning.
    # Used by Hetzner and Scaleway providers.
    class CloudInit
      def self.generate(ssh_public_key:, user: Naming.default_user)
        new(ssh_public_key:, user:).to_yaml
      end

      def initialize(ssh_public_key:, user: Naming.default_user)
        @ssh_public_key = ssh_public_key
        @user = user
      end

      def to_yaml
        <<~CLOUD_INIT
          #cloud-config
          users:
            - name: #{@user}
              groups: sudo,docker
              shell: /bin/bash
              sudo: ALL=(ALL) NOPASSWD:ALL
              ssh_authorized_keys:
                - #{@ssh_public_key}
          disable_root: true
          ssh_pwauth: false
        CLOUD_INIT
      end
    end
  end
end
