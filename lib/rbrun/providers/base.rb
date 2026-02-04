# frozen_string_literal: true

module Rbrun
  module Providers
    class Base
      def provider_name
        raise NotImplementedError
      end

      def validate!
        raise NotImplementedError
      end

      def client
        raise NotImplementedError
      end

      # Does this provider support self-hosted databases?
      def supports_self_hosted?
        false
      end

      # Is this a VM-based provider (Hetzner, Scaleway) or managed container (Daytona)?
      def vm_based?
        true
      end
    end
  end
end
