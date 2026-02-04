# frozen_string_literal: true

require "test_helper"

module Rbrun
  class SandboxTest < ActiveSupport::TestCase
    test "generates slug before validation on create" do
      sandbox = Sandbox.new
      sandbox.valid?
      assert_not_nil sandbox.slug
    end

    test "generates SSH keypair before create" do
      sandbox = Sandbox.create!
      assert_not_nil sandbox.ssh_public_key
      assert_not_nil sandbox.ssh_private_key
    end

    test "validates state inclusion" do
      sandbox = Sandbox.new(state: "invalid")
      assert_not sandbox.valid?
      assert_includes sandbox.errors[:state], "is not included in the list"
    end

    test "validates slug uniqueness" do
      sandbox1 = Sandbox.create!
      sandbox2 = Sandbox.new(slug: sandbox1.slug)
      assert_not sandbox2.valid?
      assert_includes sandbox2.errors[:slug], "has already been taken"
    end

    test "#pending? returns true when state is pending" do
      sandbox = Sandbox.new(state: "pending")
      assert sandbox.pending?
      assert_not sandbox.running?
    end

    test "#provisioning? returns true when state is provisioning" do
      sandbox = Sandbox.new(state: "provisioning")
      assert sandbox.provisioning?
    end

    test "#running? returns true when state is running" do
      sandbox = Sandbox.new(state: "running")
      assert sandbox.running?
    end

    test "#stopped? returns true when state is stopped" do
      sandbox = Sandbox.new(state: "stopped")
      assert sandbox.stopped?
    end

    test "#failed? returns true when state is failed" do
      sandbox = Sandbox.new(state: "failed")
      assert sandbox.failed?
    end

    test "#mark_failed! sets state and stores error" do
      sandbox = Sandbox.create!
      sandbox.mark_failed!("Something went wrong")
      assert_equal "failed", sandbox.state
      assert_equal "Something went wrong", sandbox.last_error
    end

    test "#mark_running! sets state to running" do
      sandbox = Sandbox.create!
      sandbox.mark_running!
      assert_equal "running", sandbox.state
    end

    test "#mark_stopped! sets state to stopped" do
      sandbox = Sandbox.create!
      sandbox.mark_stopped!
      assert_equal "stopped", sandbox.state
    end

    test "Naming.resource returns rbrun-sandbox-{slug}" do
      sandbox = Sandbox.create!
      assert_equal "rbrun-sandbox-#{sandbox.slug}", Naming.resource(sandbox.slug)
    end

    test "Naming.branch returns rbrun-sandbox/{slug}" do
      sandbox = Sandbox.create!
      assert_equal "rbrun-sandbox/#{sandbox.slug}", Naming.branch(sandbox.slug)
    end

    test "#ssh_keys_present? returns true when both keys present" do
      sandbox = Sandbox.new(ssh_public_key: "pub", ssh_private_key: "priv")
      assert sandbox.ssh_keys_present?
    end

    test "#ssh_keys_present? returns false when keys missing" do
      sandbox = Sandbox.new
      assert_not sandbox.ssh_keys_present?
    end

    test "#env_vars returns config value resolved for sandbox" do
      Rbrun.configuration.env(FOO: "bar", BAZ: { sandbox: "dev", release: "prod" })
      sandbox = Sandbox.create!
      assert_equal "bar", sandbox.env_vars[:FOO]
      assert_equal "dev", sandbox.env_vars[:BAZ]
    end

    test "#setup_commands returns config value" do
      Rbrun.configuration.setup("bundle install")
      sandbox = Sandbox.create!
      assert_equal ["bundle install"], sandbox.setup_commands
    end

    test "#env_file_content returns string for .env file" do
      Rbrun.configuration.env(FOO: "bar", BAZ: "qux")
      sandbox = Sandbox.create!
      content = sandbox.env_file_content
      assert content.include?("FOO=bar")
      assert content.include?("BAZ=qux")
    end

    test "has_many command_executions" do
      sandbox = Sandbox.create!
      exec = sandbox.command_executions.create!(command: "echo test")
      assert_includes sandbox.command_executions, exec
    end

    test "has_many sandbox_envs" do
      sandbox = Sandbox.create!
      env = sandbox.sandbox_envs.create!(key: "FOO", value: "bar")
      assert_includes sandbox.sandbox_envs, env
    end

    test "scope pending returns pending sandboxes" do
      pending = Sandbox.create!(state: "pending")
      Sandbox.create!(state: "running")
      assert_includes Sandbox.pending, pending
    end

    test "scope provisioning returns provisioning sandboxes" do
      provisioning = Sandbox.create!(state: "provisioning")
      Sandbox.create!(state: "pending")
      assert_includes Sandbox.provisioning, provisioning
    end

    test "scope running returns running sandboxes" do
      running = Sandbox.create!(state: "running")
      Sandbox.create!(state: "pending")
      assert_includes Sandbox.running, running
    end
  end
end
