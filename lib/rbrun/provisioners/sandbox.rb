# frozen_string_literal: true

module Rbrun
  module Provisioners
    # VM + Docker Compose provisioner for sandboxes.
    class Sandbox
      WORKSPACE = "/home/deploy/workspace"
      COMPOSE_FILE = "docker-compose.generated.yml"

      attr_reader :sandbox

      def initialize(sandbox)
        @sandbox = sandbox
      end

      def provision!
        return if sandbox.running?

        with_provisioning_state do
          create_infrastructure!
          install_software!
          setup_application!
          setup_tunnel! if sandbox.exposed?
        end
      end

      def deprovision!
        delete_tunnel! if sandbox.tunnel_exists?
        stop_containers! if server_exists?
        delete_infrastructure!
        sandbox.update!(state: "stopped")
        log_step("stopped")
      end

      def server_exists?
        compute_client.find_server(Naming.resource(sandbox.slug)).present?
      end

      def server_ip
        compute_client.find_server(Naming.resource(sandbox.slug))&.public_ipv4
      end

      def run_command!(command, timeout: 300)
        run_ssh!(command, timeout:)
      end

      def preview_url(port: 3000)
        return nil unless Rbrun.configuration.cloudflare_configured?
        domain = Rbrun.configuration.cloudflare_config.domain
        Naming.self_hosted_preview_url(sandbox.slug, domain)
      end

      private

        # ─────────────────────────────────────────────────────────────
        # Infrastructure
        # ─────────────────────────────────────────────────────────────

        def create_infrastructure!
          sandbox.generate_ssh_keypair unless sandbox.ssh_keys_present?
          sandbox.save! if sandbox.changed?

          log_step("firewall")
          firewall = compute_client.find_or_create_firewall(Naming.resource(sandbox.slug))

          log_step("network")
          network = compute_client.find_or_create_network(Naming.resource(sandbox.slug), location: Rbrun.configuration.compute_config.location)

          log_step("server")
          create_server!(firewall_id: firewall.id, network_id: network.id)

          log_step("ssh_wait")
          wait_for_ssh!
        end

        def delete_infrastructure!
          log_step("delete_server")
          delete_resource(:server)

          log_step("delete_network")
          delete_resource(:network)

          log_step("delete_firewall")
          delete_resource(:firewall)
        end

        def delete_resource(type)
          finder = "find_#{type}"
          deleter = "delete_#{type}"
          resource = compute_client.public_send(finder, Naming.resource(sandbox.slug))
          compute_client.public_send(deleter, resource.id) if resource
        end

        # ─────────────────────────────────────────────────────────────
        # Software Setup
        # ─────────────────────────────────────────────────────────────

        def install_software!
          log_step("apt_packages")
          run_ssh!("sudo apt-get update && sudo apt-get install -y curl git jq rsync docker.io docker-compose-v2 ca-certificates gnupg")

          log_step("docker")
          run_ssh!("sudo systemctl enable docker && sudo systemctl start docker")

          install_node! unless command_exists?("node")
          install_claude_code! unless command_exists?("claude")
          install_gh_cli! unless command_exists?("gh")

          setup_git_auth!
        end

        def install_node!
          log_step("nodejs")
          run_ssh!("curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt-get install -y nodejs")
        end

        def install_claude_code!
          log_step("claude_code")
          run_ssh!("sudo npm install -g @anthropic-ai/claude-code")
        end

        def install_gh_cli!
          log_step("gh_cli")
          run_ssh!('curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install gh -y')
        end

        def setup_git_auth!
          if git_token.present?
            log_step("gh_auth")
            run_ssh!("echo #{Shellwords.escape(git_token)} | gh auth login --with-token")
          end

          log_step("git_config")
          git_config = Rbrun.configuration.git_config
          run_ssh!("git config --global user.name '#{git_config.username}' && git config --global user.email '#{git_config.email}'")
        end

        # ─────────────────────────────────────────────────────────────
        # Application Setup
        # ─────────────────────────────────────────────────────────────

        def setup_application!
          log_step("clone")
          clone_repo!

          log_step("branch")
          checkout_branch!

          log_step("environment")
          write_environment!

          log_step("compose_generate")
          generate_compose!

          log_step("compose_setup")
          setup_docker_compose!

          log_step("ready")
        end

        def clone_repo!
          return if run_ssh!("test -d #{WORKSPACE}/.git", raise_on_error: false, timeout: 10).success?
          run_ssh!("git clone #{Shellwords.escape(git_clone_url)} #{WORKSPACE}", timeout: 120)
        end

        def checkout_branch!
          run_ssh!("cd #{WORKSPACE} && git checkout -B #{Shellwords.escape(Naming.branch(sandbox.slug))}")
        end

        def write_environment!
          env_content = sandbox.env_file_content
          return if env_content.blank?

          run_ssh!("cat > #{WORKSPACE}/.env << 'ENVEOF'\n#{env_content}\nENVEOF")
          run_ssh!("grep -qxF '.env' #{WORKSPACE}/.gitignore 2>/dev/null || echo '.env' >> #{WORKSPACE}/.gitignore")
        end

        def generate_compose!
          compose_content = Generators::Compose.new(Rbrun.configuration).generate
          run_ssh!("cat > #{WORKSPACE}/#{COMPOSE_FILE} << 'COMPOSEEOF'\n#{compose_content}\nCOMPOSEEOF")
          run_ssh!("grep -qxF '#{COMPOSE_FILE}' #{WORKSPACE}/.gitignore 2>/dev/null || echo '#{COMPOSE_FILE}' >> #{WORKSPACE}/.gitignore")
        end

        def setup_docker_compose!
          # Start databases first
          docker_compose!("up -d postgres", raise_on_error: false) if Rbrun.configuration.database?(:postgres)
          docker_compose!("up -d redis", raise_on_error: false) if Rbrun.configuration.database?(:redis) || Rbrun.configuration.service?(:redis)

          # Run setup commands
          Rbrun.configuration.setup_commands.each do |cmd|
            next if cmd.blank?
            docker_compose!("run --rm web sh -c #{Shellwords.escape(cmd)}")
          end

          # Start all services
          docker_compose!("up -d")
        end

        # ─────────────────────────────────────────────────────────────
        # Tunnel (delegates to Previewable)
        # ─────────────────────────────────────────────────────────────

        def setup_tunnel!
          return unless Rbrun.configuration.cloudflare_configured?
          log_step("tunnel_setup")
          sandbox.setup_compose_tunnel!
        end

        def delete_tunnel!
          log_step("delete_tunnel")
          sandbox.delete_compose_tunnel!
        end

        def stop_containers!
          log_step("stop_containers")
          docker_compose!("down", raise_on_error: false)
        end

        # ─────────────────────────────────────────────────────────────
        # Helpers
        # ─────────────────────────────────────────────────────────────

        def create_server!(firewall_id:, network_id:)
          user_data = Providers::CloudInit.generate(ssh_public_key: sandbox.ssh_public_key)
          config = Rbrun.configuration.compute_config

          # Resolve server_type for sandbox target
          server_type = Rbrun.configuration.resolve(config.server_type, target: :sandbox) || config.server_type

          compute_client.find_or_create_server(
            name: Naming.resource(sandbox.slug),
            server_type:,
            location: config.location,
            image: config.image,
            user_data:,
            labels: { purpose: "sandbox", sandbox_slug: sandbox.slug },
            firewalls: [firewall_id],
            networks: [network_id]
          )
        end

        def wait_for_ssh!(timeout: 180)
          sandbox.ssh_client.wait_until_ready(max_attempts: timeout / 5, interval: 5)
        end

        def run_ssh!(command, **options)
          sandbox.run_ssh!(command, **options)
        end

        def docker_compose!(args, raise_on_error: true, timeout: 300)
          run_ssh!("cd #{WORKSPACE} && docker compose -f #{COMPOSE_FILE} #{args}", raise_on_error:, timeout:)
        end

        def command_exists?(cmd)
          run_ssh!("which #{cmd}", raise_on_error: false, timeout: 10).success?
        end

        def log_step(category)
          exec = sandbox.command_executions.create!(kind: "exec", command: category, category:)
          puts "      [#{category}]"
          sandbox.broadcast_step(exec)
        end

        def with_provisioning_state
          sandbox.update!(state: "provisioning")
          yield
          sandbox.update!(state: "running")
        rescue => e
          sandbox.mark_failed!(e.message)
          raise
        end

        def compute_client
          @compute_client ||= Rbrun.configuration.compute_config.client
        end

        def git_token
          Rbrun.configuration.git_config.pat
        end

        def repo_full_name
          Rbrun.configuration.git_config.repo
        end

        def git_clone_url
          git_token.present? ? "https://#{git_token}@github.com/#{repo_full_name}.git" : "https://github.com/#{repo_full_name}.git"
        end
    end
  end
end
