# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"
require "webmock/minitest"
require "sshkey"

# Pre-generate SSH keypair once at test suite load (avoids 200-500ms per Sandbox.create)
TEST_SSH_KEY = SSHKey.generate(type: "RSA", bits: 4096, comment: "rbrun-test")

# Create test SSH key files for compute config
TEST_SSH_KEY_DIR = Dir.mktmpdir("rbrun-test-keys")
TEST_SSH_KEY_PATH = File.join(TEST_SSH_KEY_DIR, "id_rsa")
File.write(TEST_SSH_KEY_PATH, TEST_SSH_KEY.private_key)
File.write("#{TEST_SSH_KEY_PATH}.pub", TEST_SSH_KEY.ssh_public_key)
at_exit { FileUtils.rm_rf(TEST_SSH_KEY_DIR) }

# Stub configuration for all tests
module RbrunTestSetup
  def setup
    super
    Rbrun.reset_configuration!
    Rbrun.configure do |c|
      c.compute(:hetzner) do |com|
        com.api_key = "test-hetzner-key"
        com.ssh_key_path = TEST_SSH_KEY_PATH
      end

      c.cloudflare do |cf|
        cf.api_token = "test-cloudflare-key"
        cf.account_id = "test-account-id"
        cf.domain = "test.dev"
      end

      c.git do |g|
        g.pat = "test-github-token"
        g.repo = "owner/test-repo"
      end
    end

    # Stub Cloudflare API
    stub_request(:get, /api\.cloudflare\.com/)
      .to_return(status: 200, body: { success: true, result: [] }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:delete, /api\.cloudflare\.com/)
      .to_return(status: 200, body: { success: true, result: {} }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub Hetzner API (no servers exist by default)
    stub_request(:get, /api\.hetzner\.cloud/)
      .to_return(status: 200, body: { servers: [] }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub SSH key generation to use pre-generated keys (avoids slow RSA generation per test)
    Rbrun::Sandbox.define_method(:generate_ssh_keypair) do
      return if ssh_keys_present?
      self.ssh_public_key = TEST_SSH_KEY.ssh_public_key
      self.ssh_private_key = TEST_SSH_KEY.private_key
    end

    # Also stub for Release model
    if defined?(Rbrun::Release)
      Rbrun::Release.define_method(:generate_ssh_keypair) do
        return if ssh_keys_present?
        self.ssh_public_key = TEST_SSH_KEY.ssh_public_key
        self.ssh_private_key = TEST_SSH_KEY.private_key
      end
    end
  end

  def teardown
    super
    Rbrun.reset_configuration!
  end
end

class ActiveSupport::TestCase
  include RbrunTestSetup

  # Load fixtures from the engine
  if respond_to?(:fixture_paths=)
    self.fixture_paths = [File.expand_path("fixtures", __dir__)]
  end
end

class ActionDispatch::IntegrationTest
  include RbrunTestSetup
end
