# frozen_string_literal: true

module Rbrun
  class Release
    # Orchestrates K3s-based production deployment.
    # Delegates to Rbrun::Provisioners::Release for heavy lifting.
    module Provisionable
      extend ActiveSupport::Concern

      def provision!
        mark_deploying! unless deployed?
        provisioner.provision!
        mark_deployed!
      rescue StandardError => e
        mark_failed!(e.message)
        raise
      end

      def deprovision!
        provisioner.deprovision!
        mark_torn_down!
      end

      alias_method :teardown!, :deprovision!

      def redeploy!
        provisioner.redeploy!
      end

      def provisioner
        @provisioner ||= Provisioners::Release.new(self)
      end

      delegate :server_exists?, to: :provisioner
    end
  end
end
