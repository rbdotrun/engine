# frozen_string_literal: true

module Rbrun
  class CLI < Thor
    class Release < Thor
      def self.exit_on_failure?
        true
      end

      desc "deploy", "Deploy to production via K3s"
      option :env, type: :string, default: "production", desc: "Environment (staging, production, etc.)"
      option :branch, type: :string, default: "main", desc: "Git branch to deploy"
      def deploy
        load_rails!
        env = options[:env].to_sym
        Rbrun.configuration.validate_for_target!(env)

        # Reuse existing release for environment if it has infrastructure, otherwise create new
        release = Rbrun::Release.where(environment: options[:env]).where.not(server_ip: nil).last
        release ||= Rbrun::Release.create!(environment: options[:env], branch: options[:branch])
        release.update!(branch: options[:branch]) if release.branch != options[:branch]

        puts "Release: #{release.id} (#{release.environment}/#{release.branch})"
        release.provision!
        puts "URL: #{release.url}"
        puts "SSH: ssh deploy@#{release.server_ip}"
      end

      desc "destroy", "Tear down release infrastructure"
      option :env, type: :string, default: "production", desc: "Environment"
      def destroy
        load_rails!
        # Find any release with infrastructure, not just deployed ones
        release = Rbrun::Release.where(environment: options[:env]).where.not(server_ip: nil).last
        abort "No release with infrastructure for environment: #{options[:env]}" unless release
        puts "Destroying #{release.environment} release (ID: #{release.id})..."
        release.deprovision!
        release.mark_torn_down!
        puts "Done."
      end

      desc "ssh", "SSH into release server"
      option :env, type: :string, default: "production", desc: "Environment"
      def ssh
        load_rails!
        release = find_release_with_infra!
        abort "No server IP" unless release.server_ip

        # Use configured SSH key
        key_path = File.expand_path(Rbrun.configuration.compute_config.ssh_key_path)
        exec "ssh -i #{key_path} -o StrictHostKeyChecking=no deploy@#{release.server_ip}"
      end

      desc "logs", "Show pod logs"
      option :env, type: :string, default: "production", desc: "Environment"
      option :process, type: :string, default: "web", desc: "Process name"
      option :tail, type: :numeric, default: 100, desc: "Number of lines"
      def logs
        load_rails!
        release = find_release!
        release.logs(process: options[:process].to_sym, tail: options[:tail]) do |line|
          puts line
        end
      end

      desc "exec COMMAND", "Execute command in pod"
      option :env, type: :string, default: "production", desc: "Environment"
      option :process, type: :string, default: "web", desc: "Process name"
      def exec(command)
        load_rails!
        release = find_release!
        result = release.exec(command:, process: options[:process].to_sym)
        puts result.output
      end

      desc "scale REPLICAS", "Scale deployment"
      option :env, type: :string, default: "production", desc: "Environment"
      option :process, type: :string, default: "web", desc: "Process name"
      def scale(replicas)
        load_rails!
        release = find_release!
        release.scale(process: options[:process].to_sym, replicas: replicas.to_i)
        puts "Scaled #{options[:process]} to #{replicas} replicas."
      end

      desc "restart", "Restart deployment"
      option :env, type: :string, default: "production", desc: "Environment"
      option :process, type: :string, default: "web", desc: "Process name"
      def restart
        load_rails!
        release = find_release!
        release.rollout_restart(process: options[:process].to_sym)
        puts "Restarted #{options[:process]}."
      end

      private

        def find_release!
          release = Rbrun::Release.deployed.where(environment: options[:env]).last
          abort "No deployed release for environment: #{options[:env]}" unless release
          release
        end

        def find_release_with_infra!
          release = Rbrun::Release.where(environment: options[:env]).where.not(server_ip: nil).last
          abort "No release with infrastructure for environment: #{options[:env]}" unless release
          release
        end

        def load_rails!
          require File.expand_path("config/environment", Dir.pwd)
        end
    end
  end
end
