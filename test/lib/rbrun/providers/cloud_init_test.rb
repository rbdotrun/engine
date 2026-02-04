# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Providers
    class CloudInitTest < ActiveSupport::TestCase
      test ".generate returns valid cloud-config YAML" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert result.start_with?("#cloud-config")
      end

      test ".generate creates user with specified name" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...", user: "customuser")
        assert_includes result, "name: customuser"
      end

      test ".generate adds user to sudo and docker groups" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes result, "groups: sudo,docker"
      end

      test ".generate sets bash as shell" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes result, "shell: /bin/bash"
      end

      test ".generate allows passwordless sudo" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes result, "sudo: ALL=(ALL) NOPASSWD:ALL"
      end

      test ".generate adds SSH public key" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa TESTKEY123")
        assert_includes result, "ssh-rsa TESTKEY123"
      end

      test ".generate disables root login" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes result, "disable_root: true"
      end

      test ".generate disables password auth" do
        result = CloudInit.generate(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes result, "ssh_pwauth: false"
      end

      test "#to_yaml includes cloud-config header" do
        init = CloudInit.new(ssh_public_key: "ssh-rsa AAAA...")
        assert init.to_yaml.start_with?("#cloud-config")
      end

      test "#to_yaml uses deploy as default user" do
        init = CloudInit.new(ssh_public_key: "ssh-rsa AAAA...")
        assert_includes init.to_yaml, "name: deploy"
      end

      test "default user comes from Naming module" do
        assert_equal "deploy", Naming.default_user
      end
    end
  end
end
