# frozen_string_literal: true

module Rbrun
  class CLI < Thor
    class Sandbox < Thor
      def self.exit_on_failure?
        true
      end

      desc "deploy", "Deploy development sandbox"
      option :slug, type: :string, desc: "Sandbox slug"
      option :branch, type: :string, default: "main", desc: "Git branch to deploy"
      def deploy
        load_rails!
        sandbox = if options[:slug]
          Rbrun::Sandbox.find_or_create_by!(slug: options[:slug])
        else
          Rbrun::Sandbox.create!
        end
        sandbox.update!(branch: options[:branch]) if sandbox.respond_to?(:branch=)
        puts "Sandbox: #{sandbox.slug} (#{options[:branch]})"
        sandbox.provision!
        puts "URL: #{sandbox.preview_url}"
        puts "SSH: ssh deploy@#{sandbox.server_ip}"
      end

      desc "destroy", "Tear down sandbox"
      option :slug, type: :string, required: true, desc: "Sandbox slug"
      def destroy
        load_rails!
        sandbox = Rbrun::Sandbox.find_by(slug: options[:slug])
        abort "No sandbox found with slug: #{options[:slug]}" unless sandbox
        puts "Destroying #{sandbox.slug}..."
        sandbox.deprovision!
        puts "Done."
      end

      desc "ssh", "SSH into sandbox"
      option :slug, type: :string, required: true, desc: "Sandbox slug"
      def ssh
        load_rails!
        sandbox = Rbrun::Sandbox.find_by(slug: options[:slug])
        abort "No sandbox found" unless sandbox&.server_ip
        exec "ssh deploy@#{sandbox.server_ip}"
      end

      desc "logs", "Show command logs"
      option :slug, type: :string, required: true, desc: "Sandbox slug"
      def logs
        load_rails!
        sandbox = Rbrun::Sandbox.find_by(slug: options[:slug])
        abort "No sandbox found" unless sandbox
        sandbox.command_executions.order(:id).each do |e|
          puts "\n--- #{e.category || e.command.to_s.truncate(50)} (exit: #{e.exit_code}) ---"
          e.command_logs.order(:line_number).limit(20).each { |l| puts l.content }
        end
      end

      private

        def load_rails!
          require File.expand_path("config/environment", Dir.pwd)
        end
    end
  end
end
