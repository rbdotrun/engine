# frozen_string_literal: true

require "faraday"
require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"

module Rbrun
  class Engine < ::Rails::Engine
    isolate_namespace Rbrun

    # Load clients from app/clients
    config.autoload_paths << root.join("app/clients")

    # Load services from app/services
    config.autoload_paths << root.join("app/services")

    initializer "rbrun.assets" do |app|
      app.config.assets.paths << Engine.root.join("app/javascript")
      app.config.assets.paths << Engine.root.join("app/assets/stylesheets")
      app.config.assets.precompile += %w[rbrun/tailwind.css] if app.config.respond_to?(:assets)
    end

    initializer "rbrun.append_migrations" do |app|
      unless app.root.to_s.match?(root.to_s)
        config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
    end

    initializer "rbrun.action_cable" do |app|
      origins = app.config.action_cable.allowed_request_origins
      origins = origins.is_a?(Array) ? origins : [origins].compact
      origins << %r{https?://rbrun-sandbox-.*\.rb\.run}
      origins << %r{https?://localhost:\d+}
      app.config.action_cable.allowed_request_origins = origins
    end

    initializer "rbrun.dev_middleware" do |app|
      if ENV["RBRUN_DEV"]
        require_relative "dev_console_middleware"
        app.middleware.use Rbrun::DevConsoleMiddleware
      end
    end
  end
end
