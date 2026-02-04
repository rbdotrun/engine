# frozen_string_literal: true

module Rbrun
  class Sandbox
    # Git operations executed on VM via SSH (not inside container).
    # All operations create CommandExecution records for traceability.
    module GitOps
      extend ActiveSupport::Concern

      def git_pull!(token: nil, &block)
        ensure_running!

        if token.present?
          remote_url = "https://#{token}@github.com/#{Rbrun.configuration.repo}.git"
          run_git!("remote set-url origin #{Shellwords.escape(remote_url)}", &block)
        end

        run_git!("pull origin HEAD", &block)
      end

      def git_status(&block)
        ensure_running!
        run_git!("status --short", &block)
      end

      def git_log(count: 5, &block)
        ensure_running!
        run_git!("log --oneline -#{count}", &block)
      end

      def git_checkout!(ref, &block)
        ensure_running!
        run_git!("checkout #{Shellwords.escape(ref)}", &block)
      end

      private

        def run_git!(git_command, &block)
          full_command = "cd #{VM_WORKSPACE} && git #{git_command}"

          exec = command_executions.create!(
            kind: "exec",
            tag: "git",
            command: full_command
          )

          exec.execute!(&block)
          raise "Git command failed: #{git_command}" if exec.failed?

          exec.output
        end

        def ensure_running!
          raise "Sandbox not running (state: #{state})" unless state == "running"
        end
    end
  end
end
