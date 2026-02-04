# frozen_string_literal: true

require "sshkey"

module Rbrun
  class Release < ApplicationRecord
    include Release::Provisionable
    include Release::KubernetesOps
    include Concerns::DatabaseOps

    STATES = %w[pending deploying deployed failed torn_down].freeze

    has_many :command_executions, as: :executable, dependent: :destroy
    has_many :command_logs, through: :command_executions

    before_create :generate_ssh_keypair

    validates :state, inclusion: { in: STATES }

    scope :pending, -> { where(state: "pending") }
    scope :deploying, -> { where(state: "deploying") }
    scope :deployed, -> { where(state: "deployed") }
    scope :failed, -> { where(state: "failed") }
    scope :for_environment, ->(env) { where(environment: env) }

    def pending? = state == "pending"
    def deploying? = state == "deploying"
    def deployed? = state == "deployed"
    def failed? = state == "failed"
    def torn_down? = state == "torn_down"

    # ─────────────────────────────────────────────────────────────
    # Class Methods
    # ─────────────────────────────────────────────────────────────

    class << self
      def deploy!(environment: "production", branch: "main")
        release = create!(environment:, branch:)
        release.provision!
        release
      end

      def current(environment: "production")
        deployed.for_environment(environment).order(deployed_at: :desc).first
      end
    end

    # Resource prefix for this release (e.g., "myapp-production")
    def prefix
      Naming.release_prefix(Rbrun.configuration.git_config.app_name, environment)
    end

    # ─────────────────────────────────────────────────────────────
    # Instance Methods
    # ─────────────────────────────────────────────────────────────

    def url
      config = Rbrun.configuration
      return nil unless config.app? && config.app_config.web?

      web_process = config.app_config.processes[:web]
      subdomain = config.resolve(web_process&.subdomain, target: environment.to_sym)
      return nil unless subdomain

      "https://#{subdomain}.#{zone}"
    end

    # Execute command in container (K8s pod).
    # Used by shared DatabaseOps and BackupOps concerns.
    # @param command [String] Command to execute
    # @param container [Symbol] Container/process name (:app, :web, :worker)
    # @return [String] Command output
    def container_exec(command:, container: :app, &block)
      process = container == :app ? :web : container
      exec(command:, process:, &block)
    end

    def mark_failed!(error_message)
      assign_attributes(state: "failed", last_error: error_message)
      save!
    end

    def mark_deployed!
      assign_attributes(state: "deployed", deployed_at: Time.current)
      save!
    end

    def mark_deploying!
      self.state = "deploying"
      save!
    end

    def mark_torn_down!
      self.state = "torn_down"
      save!
    end

    # SSH client for remote command execution (uses config's SSH key).
    def ssh_client
      return nil unless server_ip.present?
      Ssh::Client.new(host: server_ip, private_key: Rbrun.configuration.compute_config.ssh_private_key, user: Naming.default_user)
    end

    # Execute SSH command through command_execution model.
    # ALL SSH commands MUST go through this method.
    # @param command [String] Command to execute
    # @param raise_on_error [Boolean] Raise exception on non-zero exit
    # @param timeout [Integer] Timeout in seconds (default: 300)
    # @return [CommandExecution] The execution record
    def run_ssh!(command, raise_on_error: true, timeout: 300, category: nil)
      exec = command_executions.create!(kind: "exec", command:, category:)
      exec.execute!(timeout:, raise_on_error:) do |line|
        puts "        #{line}"
      end
      exec
    end

    # Check if SSH keys are present.
    def ssh_keys_present?
      ssh_public_key.present? && ssh_private_key.present?
    end

    # Generate SSH keypair if not present.
    def generate_ssh_keypair
      return if ssh_keys_present?

      key = SSHKey.generate(type: "RSA", bits: 4096, comment: "rbrun-release")
      self.ssh_public_key = key.ssh_public_key
      self.ssh_private_key = key.private_key
    end

    private

      def zone
        Rbrun.configuration.cloudflare_config&.domain
      end
  end
end
