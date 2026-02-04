# frozen_string_literal: true

require "rbrun/version"
require "rbrun/naming"
require "rbrun/http_errors"
require "rbrun/base_client"

# Configuration
require "rbrun/configuration/git_config"
require "rbrun/configuration/claude_config"
require "rbrun/configuration"

# Generators
require "rbrun/generators/compose"
require "rbrun/generators/k3s"

# Providers
require "rbrun/providers/types"
require "rbrun/providers/base"
require "rbrun/providers/registry"
require "rbrun/providers/cloud_init"
require "rbrun/providers/hetzner/config"
require "rbrun/providers/hetzner/client"
require "rbrun/providers/scaleway/config"
require "rbrun/providers/scaleway/client"

# Kubernetes
require "rbrun/kubernetes/kubectl"
require "rbrun/kubernetes/k3s_installer"
require "rbrun/kubernetes/docker_builder"

# Cloudflare
require "rbrun/cloudflare/config"
require "rbrun/cloudflare/worker"
require "rbrun/cloudflare/client"
require "rbrun/cloudflare/r2"

# GitHub
require "rbrun/github/client"

# SSH
require "rbrun/ssh/client"

# Provisioners
require "rbrun/provisioners/sandbox"
require "rbrun/provisioners/release"

module Rbrun
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def importmap
      @importmap ||= Importmap::Map.new.tap do |map|
        map.draw(Engine.root.join("config/importmap.rb"))
      end
    end
  end
end

require "rbrun/engine" if defined?(Rails)
