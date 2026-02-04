# frozen_string_literal: true

module Rbrun
  class ClaudeConfig
    attr_accessor :auth_token, :base_url

    def initialize
      @base_url = "https://api.anthropic.com"
    end

    def configured?
      auth_token.present?
    end

    def validate!
      # Optional - no required fields
    end
  end
end
