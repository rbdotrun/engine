# frozen_string_literal: true

module Rbrun
  class GitConfig
    attr_accessor :pat, :repo, :username, :email

    def initialize
      @username = "rbrun"
      @email = "sandbox@rbrun.dev"
    end

    def validate!
      raise ConfigurationError, "git.pat is required" if pat.blank?
      raise ConfigurationError, "git.repo is required" if repo.blank?
    end
  end
end
