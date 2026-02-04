# frozen_string_literal: true

require "sshkey"

module Rbrun
  class Sandbox < ApplicationRecord
    include Sandbox::Broadcastable
    include Sandbox::GitOps
    include Sandbox::Provisionable
    include Sandbox::Previewable
    include Concerns::DatabaseOps

    STATES = %w[pending provisioning running stopped failed].freeze
    VM_WORKSPACE = "/home/deploy/workspace"

    # ─────────────────────────────────────────────────────────────
    # Execution Mode (local dev vs remote VM)
    # ─────────────────────────────────────────────────────────────

    def local?
      ENV["RBRUN_DEV"].present?
    end

    def workspace_path
      local? ? Rails.root.to_s : VM_WORKSPACE
    end

    def claude_bin
      local? ? (`which claude`.strip.presence || "/opt/homebrew/bin/claude") : "claude"
    end

    has_many :command_executions, as: :executable, dependent: :destroy
    has_many :command_logs, through: :command_executions
    has_many :sandbox_envs, dependent: :destroy
    has_many :claude_sessions, dependent: :destroy

    before_validation :generate_slug, on: :create
    before_create :generate_ssh_keypair
    before_create :generate_access_token

    validates :slug, presence: true, uniqueness: true, format: { with: Naming::SLUG_REGEX }
    validates :state, inclusion: { in: STATES }

    scope :pending, -> { where(state: "pending") }
    scope :provisioning, -> { where(state: "provisioning") }
    scope :running, -> { where(state: "running") }

    def pending? = state == "pending"
    def provisioning? = state == "provisioning"
    def running? = state == "running"
    def stopped? = state == "stopped"
    def failed? = state == "failed"

    def mark_failed!(error_message)
      assign_attributes(state: "failed", last_error: error_message)
      save!
    end

    def mark_running!
      self.state = "running"
      save!
    end

    def mark_stopped!
      self.state = "stopped"
      save!
    end

    # Enqueue provisioning job.
    def provision_later!
      ProvisionSandboxJob.perform_later(self)
    end

    # Enqueue deprovisioning job.
    def deprovision_later!
      DeprovisionSandboxJob.perform_later(self)
    end

    # Deprovision synchronously with broadcasting.
    def deprovision_now!
      deprovision!
    end

    # Provision synchronously with broadcasting.
    def provision_now!
      provision!
    end

    # SSH client for remote command execution.
    def ssh_client
      ip = server_ip
      return nil unless ip.present?
      Ssh::Client.new(host: ip, private_key: ssh_private_key, user: Naming.default_user)
    end

    # Docker network name for this sandbox.
    def docker_network
      Naming.resource(slug)
    end

    # App container name.
    def app_container
      Naming.container(slug, "app")
    end

    # Preview URL with authentication token.
    def authenticated_preview_url
      return nil unless preview_url && access_token
      "#{preview_url}?token=#{access_token}"
    end

    # Check if SSH keys are present.
    def ssh_keys_present?
      ssh_public_key.present? && ssh_private_key.present?
    end

    # Generate SSH keypair if not present.
    def generate_ssh_keypair
      return if ssh_keys_present?

      key = SSHKey.generate(type: "RSA", bits: 4096, comment: Naming.ssh_comment(slug))
      self.ssh_public_key = key.ssh_public_key
      self.ssh_private_key = key.private_key
    end

    # Get setup commands from config
    def setup_commands
      Rbrun.configuration.setup_commands || []
    end

    # Get environment variables from config (resolved for sandbox target)
    def env_vars
      config = Rbrun.configuration
      (config.env_vars || {}).transform_values do |v|
        config.resolve(v, target: :sandbox)
      end
    end

    # Environment as string for .env file
    def env_file_content
      env_vars.map { |k, v| "#{k}=#{v}" }.join("\n")
    end

    # Execute SSH command through command_execution model.
    # ALL SSH commands MUST go through this method.
    # @param command [String] Command to execute
    # @param raise_on_error [Boolean] Raise exception on non-zero exit
    # @param timeout [Integer] Timeout in seconds (default: 300)
    # @return [CommandExecution] The execution record
    def run_ssh!(command, raise_on_error: true, timeout: 300)
      exec = command_executions.create!(kind: "exec", command:)
      exec.execute!(timeout:, raise_on_error:) do |line|
        puts "        #{line}"
        broadcast_output(exec, line)
      end
      exec
    end

    # Run Claude Code prompt on the sandbox.
    # @param prompt [String] The prompt to send to Claude Code
    # @param session [ClaudeSession] Optional session for conversation continuity
    # @param timeout [Integer] Timeout in seconds (default: 600)
    # @yield [line] Called for each line of output (for streaming)
    # @return [CommandExecution] The execution record
    def run_claude!(prompt, session: nil, timeout: 600, &block)
      local? ? run_claude_locally!(prompt, session:, timeout:, &block) : run_claude_remote!(prompt, session:, timeout:, &block)
    end

    # Execute shell command (local or remote).
    # @param command [String] Command to execute
    # @param timeout [Integer] Timeout in seconds
    # @yield [line] Called for each line of output
    # @return [String] Command output (local) or CommandExecution (remote)
    def shell_exec(command, timeout: 300, &block)
      local? ? `#{command}` : run_ssh!(command, raise_on_error: false, timeout:, &block).output
    end

    # Execute SSH command with streaming output.
    # @param command [String] Command to execute
    # @param session [ClaudeSession] Optional session to associate with execution
    # @param timeout [Integer] Timeout in seconds
    # @yield [line] Called for each line of output
    # @return [CommandExecution] The execution record
    def run_ssh_with_streaming!(command, session: nil, timeout: 300, &block)
      exec = command_executions.create!(kind: "exec", command:, claude_session: session)
      exec.execute!(timeout:) do |line|
        broadcast_output(exec, line)
        block&.call(line)
      end
      exec
    end

    # Execute command in container (Docker Compose).
    # Used by shared DatabaseOps and BackupOps concerns.
    # @param command [String] Command to execute
    # @param container [Symbol] Container name (:app, :postgres, :redis)
    # @return [CommandExecution] The execution record
    def container_exec(command:, container: :app, &block)
      container_name = case container
      when :app then app_container
      when :postgres then Naming.container(slug, "postgres")
      when :redis then Naming.container(slug, "redis")
      else Naming.container(slug, container.to_s)
      end

      docker_cmd = "docker exec #{container_name} sh -c #{Shellwords.escape(command)}"
      run_ssh!(docker_cmd, raise_on_error: false, &block)
    end

    private

      def generate_slug
        self.slug ||= Naming.generate_slug
      end

      def generate_access_token
        self.access_token ||= SecureRandom.urlsafe_base64(32)
      end

      def run_claude_locally!(prompt, session: nil, timeout: 600, &block)
        require "open3"

        cmd = build_claude_command(session)
        exec = command_executions.create!(kind: "exec", command: cmd, claude_session: session)

        Open3.popen3(cmd, chdir: workspace_path) do |stdin, stdout, stderr, wait_thr|
          stdin.puts(prompt)
          stdin.close
          stdout.each_line { |line| block&.call(line) }
          exec.update!(exit_code: wait_thr.value.exitstatus)
        end

        exec
      end

      def run_claude_remote!(prompt, session: nil, timeout: 600, &block)
        raise "Claude not configured" unless Rbrun.configuration.claude_configured?
        raise "Sandbox not running" unless running?

        cmd = "cd #{workspace_path} && #{claude_env_vars} #{build_claude_command(session)} #{Shellwords.escape(prompt)}"
        run_ssh_with_streaming!(cmd, session:, timeout:, &block)
      end

      def build_claude_command(session = nil)
        session_args = session ? "#{session.cli_flag} #{session.session_uuid}" : ""
        "#{claude_bin} #{session_args} -p --dangerously-skip-permissions --output-format=stream-json --verbose"
      end

      def claude_env_vars
        claude = Rbrun.configuration.claude_config
        "ANTHROPIC_API_KEY=#{claude.auth_token} ANTHROPIC_BASE_URL=#{claude.base_url}"
      end
  end
end
