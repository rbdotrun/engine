# frozen_string_literal: true

module Rbrun
  class ClaudeSession
    # Handles running Claude Code prompts via the parent sandbox.
    # Delegates local/remote decision to sandbox.local?
    module Runnable
      extend ActiveSupport::Concern

      def run_claude!(prompt, timeout: 600, &block)
        exec = command_executions.create!(
          executable: sandbox,
          kind: "exec",
          command: build_claude_command
        )

        exec.update!(started_at: Time.current)

        # Store and broadcast user prompt as first log line
        user_message = { type: "user", text: prompt }.to_json
        exec.send(:store_output!, user_message) { |l| block&.call(l) }

        sandbox.local? ? run_locally(prompt, exec, &block) : run_remote(prompt, exec, timeout:, &block)

        capture_git_diff!
        exec
      end

      private

        def build_claude_command
          "#{sandbox.claude_bin} #{cli_flag} #{session_uuid} -p --dangerously-skip-permissions --output-format=stream-json --verbose"
        end

        def run_locally(prompt, exec, &block)
          require "open3"

          Open3.popen3(exec.command, chdir: sandbox.workspace_path) do |stdin, stdout, stderr, wait_thr|
            stdin.puts(prompt)
            stdin.close
            stdout.each_line { |line| block.call(line) }
            exec.update!(exit_code: wait_thr.value.exitstatus, finished_at: Time.current)
          end
        end

        def run_remote(prompt, exec, timeout:, &block)
          raise "Claude not configured" unless Rbrun.configuration.claude_configured?
          raise "Sandbox not running" unless sandbox.running?

          claude = Rbrun.configuration.claude_config
          env = "ANTHROPIC_API_KEY=#{claude.auth_token} ANTHROPIC_BASE_URL=#{claude.base_url}"
          cmd = "cd #{sandbox.workspace_path} && #{env} #{exec.command} #{Shellwords.escape(prompt)}"

          ssh_exec = sandbox.run_ssh_with_streaming!(cmd, session: self, timeout:, &block)
          exec.update!(exit_code: ssh_exec.exit_code, finished_at: Time.current)
        end

        def capture_git_diff!
          diff = sandbox.shell_exec("cd #{sandbox.workspace_path} && git diff 2>/dev/null").presence
          update!(git_diff: diff)
        rescue => e
          Rails.logger.error("[ClaudeSession] Failed to capture git diff: #{e.message}")
        end
    end
  end
end
