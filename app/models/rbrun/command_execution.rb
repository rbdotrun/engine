# frozen_string_literal: true

module Rbrun
  # == Schema Information
  #
  # Table name: rbrun_command_executions
  #
  #  id           :integer          not null, primary key
  #  sandbox_id   :integer          not null
  #  command      :text             not null
  #  kind         :string           default("exec"), not null
  #  tag          :string
  #  category     :string
  #  exit_code    :integer
  #  started_at   :datetime
  #  finished_at  :datetime
  #  image        :string
  #  container_id :string
  #  port         :integer
  #  public       :boolean          default(false)
  #  created_at   :datetime
  #  updated_at   :datetime
  #
  class CommandExecution < ApplicationRecord
    KINDS = %w[exec process].freeze

    TAGS = %w[service app tunnel provision validate ready run git discovery ingest build system].freeze

    CATEGORIES = {
      "ssh_key" => "Registering SSH key...",
      "firewall" => "Creating firewall...",
      "network" => "Creating Hetzner network...",
      "server" => "Creating server...",
      "ssh_wait" => "Waiting for SSH...",
      "apt_update" => "Updating packages...",
      "apt_packages" => "Installing packages...",
      "docker" => "Starting Docker...",
      "nodejs" => "Installing Node.js...",
      "claude_code" => "Installing Claude Code...",
      "git_config" => "Configuring Git...",
      "clone" => "Cloning repository...",
      "branch" => "Creating branch...",
      "environment" => "Writing environment...",
      "compose_setup" => "Setting up Docker Compose...",
      "tunnel_setup" => "Setting up tunnel...",
      "ready" => "Sandbox ready!",
      "delete_tunnel" => "Deleting tunnel...",
      "stop_containers" => "Stopping containers...",
      "delete_server" => "Deleting server...",
      "delete_network" => "Deleting Hetzner network...",
      "delete_firewall" => "Deleting firewall...",
      "stopped" => "Sandbox stopped."
    }.freeze

    def category_label
      CATEGORIES[category] || category&.titleize || command.truncate(50)
    end

    belongs_to :executable, polymorphic: true
    belongs_to :claude_session, optional: true
    has_many :command_logs, dependent: :destroy

    # Backwards compatibility alias
    def sandbox
      executable if executable.is_a?(Sandbox)
    end

    validates :command, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :tag, inclusion: { in: TAGS }, allow_nil: true

    scope :exec_kind, -> { where(kind: "exec") }
    scope :process_kind, -> { where(kind: "process") }
    scope :by_tag, ->(tag) { where(tag:) }

    def exec? = kind == "exec"
    def process? = kind == "process"
    def public? = public == true

    # Execute via SSH to the VM.
    # @param timeout [Integer] Command timeout in seconds (default: 300)
    # @param raise_on_error [Boolean] Re-raise exceptions on failure (default: true)
    def execute!(timeout: 300, raise_on_error: true, &block)
      ssh = executable&.ssh_client
      raise "No SSH connection available" unless ssh

      update!(started_at: Time.current)

      begin
        result = ssh.execute(command, timeout:, raise_on_error: false) do |line|
          store_output!(line, &block)
        end

        update!(exit_code: result[:exit_code], finished_at: Time.current)

        if raise_on_error && result[:exit_code] != 0
          raise Ssh::Client::Error.new("Command failed with exit code #{result[:exit_code]}: #{command}")
        end

        result
      rescue Ssh::Client::Error => e
        code = e.respond_to?(:exit_code) ? e.exit_code : -1
        update!(exit_code: code, finished_at: Time.current) unless finished_at
        store_output!(e.respond_to?(:output) ? e.output : e.message, stream: "stderr", &block)
        raise if raise_on_error
      end
    end

    def output
      command_logs.output.pluck(:content).join("\n")
    end

    def success? = exit_code == 0
    def failed? = exit_code && exit_code != 0

    private

      def store_output!(content, stream: "output", &block)
        return if content.blank?

        content_utf8 = content.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

        base_line = command_logs.where(stream:).maximum(:line_number) || 0

        content_utf8.split("\n").each_with_index do |line_content, idx|
          next if line_content.blank?

          command_logs.create!(stream:, line_number: base_line + idx + 1, content: line_content)
          yield line_content if block_given?
        end
      end
  end
end
