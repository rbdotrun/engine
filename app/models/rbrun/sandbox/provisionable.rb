# frozen_string_literal: true

module Rbrun
  class Sandbox
    # Thin orchestrator that delegates provisioning to strategy classes.
    # See lib/rbrun/provisioners/ for VM and Container implementations.
    module Provisionable
      extend ActiveSupport::Concern

      def provision!
        return if running?
        provisioner.provision!
      end

      def deprovision!
        provisioner.deprovision!
      end

      def provisioner
        @provisioner ||= Provisioners::Sandbox.new(self)
      end

      delegate :server_exists?, :server_ip, :run_command!, to: :provisioner

      def preview_url
        provisioner.preview_url
      end
    end
  end
end
