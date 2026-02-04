require_relative "lib/rbrun/version"

Gem::Specification.new do |spec|
  spec.name        = "rbrun"
  spec.version     = Rbrun::VERSION
  spec.authors     = [ "Ben" ]
  spec.email       = [ "ben@dee.mx" ]
  spec.homepage    = "https://github.com/rbdotrun/engine"
  spec.summary     = "Ephemeral cloud development environments for Rails apps"
  spec.description = "A Rails engine for provisioning Hetzner VMs with Cloudflare Tunnel preview URLs"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib,exe}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.bindir = "exe"
  spec.executables = ["rbrun"]

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "net-scp", "~> 4.0"
  spec.add_dependency "sshkey", "~> 3.0"
  spec.add_dependency "turbo-rails", ">= 1.0"
  spec.add_dependency "stimulus-rails"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "tailwindcss-rails", "~> 4.0"
  spec.add_dependency "aws-sdk-s3", "~> 1.0"  # For R2 storage
end
