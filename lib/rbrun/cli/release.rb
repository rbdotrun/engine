# frozen_string_literal: true

module Rbrun
  class CLI < Thor
    class Release < Thor
      def self.exit_on_failure?
        true
      end

      desc "deploy", "Deploy to production via K3s"
      def deploy
        load_rails!
        release = Rbrun::Release.create!
        puts "Release: #{release.id}"
        release.provision!
        puts "URL: #{release.url}"
        puts "SSH: ssh deploy@#{release.server_ip}"
      end

      desc "destroy", "Tear down release infrastructure"
      def destroy
        load_rails!
        release = Rbrun::Release.last
        abort "No release found" unless release
        puts "Destroying release #{release.id}..."
        release.deprovision!
        release.mark_torn_down!
        puts "Done."
      end

      desc "ssh", "SSH into release server"
      def ssh
        load_rails!
        release = Rbrun::Release.deployed.last
        abort "No deployed release" unless release&.server_ip
        exec "ssh deploy@#{release.server_ip}"
      end

      desc "logs", "Show pod logs"
      option :process, type: :string, default: "web", desc: "Process name"
      option :tail, type: :numeric, default: 100, desc: "Number of lines"
      def logs
        load_rails!
        release = Rbrun::Release.deployed.last
        abort "No deployed release" unless release
        release.logs(process: options[:process].to_sym, tail: options[:tail]) do |line|
          puts line
        end
      end

      desc "exec COMMAND", "Execute command in pod"
      option :process, type: :string, default: "web", desc: "Process name"
      def exec(command)
        load_rails!
        release = Rbrun::Release.deployed.last
        abort "No deployed release" unless release
        result = release.exec(command:, process: options[:process].to_sym)
        puts result.output
      end

      desc "scale REPLICAS", "Scale deployment"
      option :process, type: :string, default: "web", desc: "Process name"
      def scale(replicas)
        load_rails!
        release = Rbrun::Release.deployed.last
        abort "No deployed release" unless release
        release.scale(process: options[:process].to_sym, replicas: replicas.to_i)
        puts "Scaled #{options[:process]} to #{replicas} replicas."
      end

      desc "restart", "Restart deployment"
      option :process, type: :string, default: "web", desc: "Process name"
      def restart
        load_rails!
        release = Rbrun::Release.deployed.last
        abort "No deployed release" unless release
        release.rollout_restart(process: options[:process].to_sym)
        puts "Restarted #{options[:process]}."
      end

      private

        def load_rails!
          require File.expand_path("config/environment", Dir.pwd)
        end
    end
  end
end
