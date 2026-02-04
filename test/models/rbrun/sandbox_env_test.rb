# frozen_string_literal: true

require "test_helper"

module Rbrun
  class SandboxEnvTest < ActiveSupport::TestCase
    def setup
      super
      @sandbox = Sandbox.create!
    end

    test "validates key presence" do
      env = SandboxEnv.new(sandbox: @sandbox, value: "test")
      assert_not env.valid?
      assert_includes env.errors[:key], "can't be blank"
    end

    test "validates key format allows uppercase letters" do
      env = SandboxEnv.new(sandbox: @sandbox, key: "FOO", value: "bar")
      assert env.valid?
    end

    test "validates key format allows underscores" do
      env = SandboxEnv.new(sandbox: @sandbox, key: "FOO_BAR", value: "baz")
      assert env.valid?
    end

    test "validates key format allows numbers after first char" do
      env = SandboxEnv.new(sandbox: @sandbox, key: "FOO123", value: "bar")
      assert env.valid?
    end

    test "validates key format rejects lowercase" do
      env = SandboxEnv.new(sandbox: @sandbox, key: "foo", value: "bar")
      assert_not env.valid?
      assert_includes env.errors[:key], "must be uppercase with underscores"
    end

    test "validates key format rejects starting with number" do
      env = SandboxEnv.new(sandbox: @sandbox, key: "123FOO", value: "bar")
      assert_not env.valid?
      assert_includes env.errors[:key], "must be uppercase with underscores"
    end

    test "validates key uniqueness per sandbox" do
      @sandbox.sandbox_envs.create!(key: "FOO", value: "bar")
      duplicate = SandboxEnv.new(sandbox: @sandbox, key: "FOO", value: "baz")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:key], "has already been taken"
    end

    test "allows same key on different sandboxes" do
      sandbox2 = Sandbox.create!
      @sandbox.sandbox_envs.create!(key: "FOO", value: "bar")
      env2 = SandboxEnv.new(sandbox: sandbox2, key: "FOO", value: "baz")
      assert env2.valid?
    end

    test "belongs_to sandbox" do
      env = @sandbox.sandbox_envs.create!(key: "FOO", value: "bar")
      assert_equal @sandbox, env.sandbox
    end
  end
end
