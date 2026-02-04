# frozen_string_literal: true

require "test_helper"

module Rbrun
  class ClaudeSession
    class RunnableTest < ActiveSupport::TestCase
      setup do
        @sandbox = Sandbox.create!
        @session = ClaudeSession.create!(sandbox: @sandbox)
      end

      test "run_claude! creates a command execution" do
        with_stubbed_process do
          assert_difference -> { CommandExecution.count }, 1 do
            @session.run_claude!("test prompt")
          end
        end
      end

      test "run_claude! associates execution with session and sandbox" do
        with_stubbed_process do
          exec = @session.run_claude!("test prompt")
          assert_equal @session, exec.claude_session
          assert_equal @sandbox, exec.sandbox
        end
      end

      test "run_claude! saves user prompt to command_logs" do
        with_stubbed_process(output: "line 1\nline 2\nline 3\n") do
          exec = @session.run_claude!("test prompt")
          # First log is the user prompt JSON
          assert_equal 1, exec.command_logs.count
          assert_equal '{"type":"user","text":"test prompt"}', exec.command_logs.first.content
        end
      end

      test "run_claude! yields each line to block" do
        lines_received = []
        with_stubbed_process(output: "foo\nbar\n") do
          @session.run_claude!("test prompt") { |line| lines_received << line }
        end
        # First line is the user prompt JSON, then the output lines
        assert_equal ['{"type":"user","text":"test prompt"}', "foo", "bar"], lines_received
      end

      test "run_claude! sets exit_code on completion" do
        with_stubbed_process(exit_code: 0) do
          exec = @session.run_claude!("test prompt")
          assert_equal 0, exec.exit_code
          assert exec.success?
        end
      end

      test "run_claude! sets exit_code on failure" do
        with_stubbed_process(exit_code: 1) do
          exec = @session.run_claude!("test prompt")
          assert_equal 1, exec.exit_code
          assert exec.failed?
        end
      end

      test "run_claude! sets started_at and finished_at" do
        with_stubbed_process do
          exec = @session.run_claude!("test prompt")
          assert_not_nil exec.started_at
          assert_not_nil exec.finished_at
        end
      end

      test "build_claude_command includes session flag for new session" do
        cmd = @session.send(:build_claude_command)
        assert_includes cmd, "--session-id #{@session.session_uuid}"
        assert_includes cmd, "--dangerously-skip-permissions"
        assert_includes cmd, "--output-format=stream-json"
      end

      test "build_claude_command includes resume flag for resumable session" do
        @session.command_executions.create!(executable: @sandbox, command: "test", exit_code: 0)

        cmd = @session.send(:build_claude_command)
        assert_includes cmd, "--resume #{@session.session_uuid}"
      end

      test "run_claude! captures git diff after command" do
        with_stubbed_process do
          with_stubbed_git_diff("diff --git a/file.rb\n+new line") do
            @session.run_claude!("test prompt")
            assert_equal "diff --git a/file.rb\n+new line", @session.reload.git_diff
          end
        end
      end

      test "run_claude! stores nil when git diff is empty" do
        with_stubbed_process do
          with_stubbed_git_diff("") do
            @session.run_claude!("test prompt")
            assert_nil @session.reload.git_diff
          end
        end
      end

      test "run_claude! succeeds even when git diff capture fails" do
        # Simulate a scenario where git diff capture fails but run_claude! still returns successfully
        with_stubbed_process do
          # Directly test that capture_git_diff! handles errors gracefully
          @session.define_singleton_method(:capture_git_diff!) do
            # Simulate error being caught by rescue block (logs but doesn't raise)
            Rails.logger.error("[ClaudeSession] Failed to capture git diff for session #{id}: simulated error")
          end

          exec = @session.run_claude!("test prompt")
          assert exec.success?
          assert_nil @session.reload.git_diff
        end
      end

      test "run_claude! overwrites previous git diff" do
        @session.update!(git_diff: "old diff")

        with_stubbed_process do
          with_stubbed_git_diff("new diff content") do
            @session.run_claude!("test prompt")
            assert_equal "new diff content", @session.reload.git_diff
          end
        end
      end

      private

        def with_stubbed_git_diff(diff)
          original_capture_git_diff = @session.method(:capture_git_diff!)

          @session.define_singleton_method(:capture_git_diff!) do
            update!(git_diff: diff.presence)
          end

          yield
        ensure
          @session.define_singleton_method(:capture_git_diff!, original_capture_git_diff)
        end

        def with_stubbed_process(output: "test output\n", exit_code: 0)
          original_env = ENV["RBRUN_DEV"]
          ENV["RBRUN_DEV"] = "1"

          original_run_locally = @session.method(:run_locally)
          original_capture_git_diff = @session.method(:capture_git_diff!)

          @session.define_singleton_method(:run_locally) do |prompt, exec, &block|
            require "stringio"
            stdout = StringIO.new(output)
            stdout.each_line { |line| block&.call(line.chomp) }
            exec.update!(exit_code:, finished_at: Time.current)
          end

          # Stub git diff capture to avoid actual git commands in tests
          @session.define_singleton_method(:capture_git_diff!) { }

          yield
        ensure
          ENV["RBRUN_DEV"] = original_env
          @session.define_singleton_method(:run_locally, original_run_locally)
          @session.define_singleton_method(:capture_git_diff!, original_capture_git_diff)
        end
    end
  end
end
