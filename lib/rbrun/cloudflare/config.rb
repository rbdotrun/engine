# frozen_string_literal: true

module Rbrun
  module Cloudflare
    class Config
      attr_accessor :api_token, :account_id, :domain, :storage_bucket

      def configured?
        api_token.present? && account_id.present? && domain.present?
      end

      def validate!
        return unless configured?
        raise ConfigurationError, "cloudflare.api_token is required" if api_token.blank?
        raise ConfigurationError, "cloudflare.account_id is required" if account_id.blank?
        raise ConfigurationError, "cloudflare.domain is required" if domain.blank?
      end

      def client
        @client ||= Client.new(api_token:, account_id:)
      end

      def r2
        @r2 ||= R2.new(api_token:, account_id:)
      end

      def zone_id
        @zone_id ||= client.get_zone_id(domain)
      end
    end
  end
end
