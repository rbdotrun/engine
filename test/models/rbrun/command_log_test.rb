# frozen_string_literal: true

require "test_helper"

module Rbrun
  class CommandLogTest < ActiveSupport::TestCase
    def setup
      super
      @sandbox = Sandbox.create!
      @execution = @sandbox.command_executions.create!(command: "echo test")
    end

    test "validates stream presence" do
      log = CommandLog.new(command_execution: @execution, line_number: 1, content: "test")
      assert_not log.valid?
      assert_includes log.errors[:stream], "can't be blank"
    end

    test "validates line_number greater than 0" do
      log = CommandLog.new(command_execution: @execution, stream: "output", line_number: 0, content: "test")
      assert_not log.valid?
      assert_includes log.errors[:line_number], "must be greater than 0"
    end

    test "validates content presence" do
      log = CommandLog.new(command_execution: @execution, stream: "output", line_number: 1)
      assert_not log.valid?
      assert_includes log.errors[:content], "can't be blank"
    end

    test "belongs_to command_execution" do
      log = @execution.command_logs.create!(stream: "output", line_number: 1, content: "test")
      assert_equal @execution, log.command_execution
    end

    test "scope stdout filters stream=stdout" do
      stdout = @execution.command_logs.create!(stream: "stdout", line_number: 1, content: "test")
      stderr = @execution.command_logs.create!(stream: "stderr", line_number: 2, content: "test")
      assert_includes CommandLog.stdout, stdout
      assert_not_includes CommandLog.stdout, stderr
    end

    test "scope stderr filters stream=stderr" do
      stderr = @execution.command_logs.create!(stream: "stderr", line_number: 1, content: "test")
      stdout = @execution.command_logs.create!(stream: "stdout", line_number: 2, content: "test")
      assert_includes CommandLog.stderr, stderr
      assert_not_includes CommandLog.stderr, stdout
    end

    test "scope output filters stream=output" do
      output = @execution.command_logs.create!(stream: "output", line_number: 1, content: "test")
      stdout = @execution.command_logs.create!(stream: "stdout", line_number: 2, content: "test")
      assert_includes CommandLog.output, output
      assert_not_includes CommandLog.output, stdout
    end

    test "scope ordered sorts by line_number" do
      log2 = @execution.command_logs.create!(stream: "output", line_number: 2, content: "second")
      log1 = @execution.command_logs.create!(stream: "output", line_number: 1, content: "first")
      logs = @execution.command_logs.ordered
      assert_equal [log1, log2], logs.to_a
    end
  end
end
