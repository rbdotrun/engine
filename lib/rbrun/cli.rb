# frozen_string_literal: true

require "thor"
require_relative "cli/release"
require_relative "cli/sandbox"

module Rbrun
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "release SUBCOMMAND", "Manage production releases"
    subcommand "release", Rbrun::CLI::Release

    desc "sandbox SUBCOMMAND", "Manage development sandboxes"
    subcommand "sandbox", Rbrun::CLI::Sandbox

    desc "status", "Show deployment status"
    def status
      load_rails!
      puts "Releases: #{Rbrun::Release.count}"
      puts "Sandboxes: #{Rbrun::Sandbox.count}"
    end

    desc "config", "Validate configuration"
    def config
      load_rails!
      Rbrun.configuration.validate!
      puts "Configuration valid."
    rescue Rbrun::ConfigurationError => e
      abort "Configuration error: #{e.message}"
    end

    private

      def load_rails!
        require File.expand_path("config/environment", Dir.pwd)
      end
  end
end
