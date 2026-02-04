# frozen_string_literal: true

require "test_helper"

module Rbrun
  class CommandExecutionTest < ActiveSupport::TestCase
    def setup
      super
      @sandbox = Sandbox.create!
    end

    test "validates command presence" do
      exec = CommandExecution.new(executable: @sandbox)
      assert_not exec.valid?
      assert_includes exec.errors[:command], "can't be blank"
    end

    test "validates kind inclusion" do
      exec = CommandExecution.new(executable: @sandbox, command: "test", kind: "invalid")
      assert_not exec.valid?
      assert_includes exec.errors[:kind], "is not included in the list"
    end

    test "validates tag inclusion when present" do
      exec = CommandExecution.new(executable: @sandbox, command: "test", tag: "invalid")
      assert_not exec.valid?
      assert_includes exec.errors[:tag], "is not included in the list"
    end

    test "allows nil tag" do
      exec = CommandExecution.new(executable: @sandbox, command: "test", tag: nil)
      assert exec.valid?
    end

    test "belongs_to sandbox" do
      exec = @sandbox.command_executions.create!(command: "echo test")
      assert_equal @sandbox, exec.sandbox
    end

    test "has_many command_logs" do
      exec = @sandbox.command_executions.create!(command: "echo test")
      log = exec.command_logs.create!(stream: "output", line_number: 1, content: "test")
      assert_includes exec.command_logs, log
    end

    test "#exec? returns true when kind is exec" do
      exec = CommandExecution.new(kind: "exec")
      assert exec.exec?
      assert_not exec.process?
    end

    test "#process? returns true when kind is process" do
      exec = CommandExecution.new(kind: "process")
      assert exec.process?
      assert_not exec.exec?
    end

    test "#success? returns true when exit_code is 0" do
      exec = CommandExecution.new(exit_code: 0)
      assert exec.success?
    end

    test "#failed? returns true when exit_code is non-zero" do
      exec = CommandExecution.new(exit_code: 1)
      assert exec.failed?
    end

    test "#failed? returns false when exit_code is nil" do
      exec = CommandExecution.new(exit_code: nil)
      assert_not exec.failed?
    end

    test "#output returns concatenated command_logs content" do
      exec = @sandbox.command_executions.create!(command: "echo test")
      exec.command_logs.create!(stream: "output", line_number: 1, content: "line1")
      exec.command_logs.create!(stream: "output", line_number: 2, content: "line2")
      assert_equal "line1\nline2", exec.output
    end

    test "#category_label returns CATEGORIES mapping" do
      exec = CommandExecution.new(command: "test", category: "firewall")
      assert_equal "Creating firewall...", exec.category_label
    end

    test "#category_label titleizes unknown categories" do
      exec = CommandExecution.new(command: "test", category: "custom_step")
      assert_equal "Custom Step", exec.category_label
    end

    test "#category_label truncates command as fallback" do
      long_command = "a" * 100
      exec = CommandExecution.new(command: long_command, category: nil)
      assert_equal long_command.truncate(50), exec.category_label
    end

    test "scope exec_kind filters by exec" do
      exec = @sandbox.command_executions.create!(command: "test", kind: "exec")
      process = @sandbox.command_executions.create!(command: "test", kind: "process")
      assert_includes CommandExecution.exec_kind, exec
      assert_not_includes CommandExecution.exec_kind, process
    end

    test "scope process_kind filters by process" do
      process = @sandbox.command_executions.create!(command: "test", kind: "process")
      exec = @sandbox.command_executions.create!(command: "test", kind: "exec")
      assert_includes CommandExecution.process_kind, process
      assert_not_includes CommandExecution.process_kind, exec
    end

    test "scope by_tag filters by tag" do
      git = @sandbox.command_executions.create!(command: "test", tag: "git")
      tunnel = @sandbox.command_executions.create!(command: "test", tag: "tunnel")
      assert_includes CommandExecution.by_tag("git"), git
      assert_not_includes CommandExecution.by_tag("git"), tunnel
    end
  end
end
