# frozen_string_literal: true

namespace :rbrun do
  # ─────────────────────────────────────────────────────────────
  # Build Tasks
  # ─────────────────────────────────────────────────────────────

  desc "Build Tailwind CSS"
  task tailwind_build: :environment do
    require "tailwindcss-rails"
    input = Rbrun::Engine.root.join("app/assets/stylesheets/rbrun/engine.css").to_s
    output = Rbrun::Engine.root.join("app/assets/stylesheets/rbrun/tailwind.css").to_s
    system(Tailwindcss::Commands.compile_command.first, "-i", input, "-o", output)
  end

  desc "Build React console"
  task console_build: :environment do
    dir = Rbrun::Engine.root.join("console")
    system("cd #{dir} && npm install && npm run build")
  end

  # ─────────────────────────────────────────────────────────────
  # Sandbox: VM + Docker Compose + Claude Code
  # ─────────────────────────────────────────────────────────────

  desc "Deploy sandbox and verify Claude Code + app"
  task sandbox: :environment do
    load_env!
    configure_sandbox!

    puts "=== Sandbox Deploy ==="
    sandbox = Rbrun::Sandbox.find_or_create_by!(slug: "a1b2c3")
    sandbox.update!(exposed: true) unless sandbox.exposed?
    puts "Sandbox: #{sandbox.slug}"

    # Provision
    puts "\n[1] Provisioning..."
    sandbox.provision!
    puts "    IP: #{sandbox.server_ip}"
    puts "    URL: #{sandbox.preview_url}"

    # Health check (use token URL for Cloudflare Worker auth)
    puts "\n[2] Health check..."
    health_url = if sandbox.preview_url && sandbox.access_token
                   "#{sandbox.preview_url}?token=#{sandbox.access_token}"
                 else
                   "http://#{sandbox.server_ip}:3000"
                 end
    wait_for_http!(health_url)

    # Claude Code
    puts "\n[3] Claude Code..."
    session = sandbox.claude_sessions.create!
    exec = session.run_claude!("List files in app/models. One sentence each.")
    raise "Claude failed: exit #{exec.exit_code}" unless exec.success?
    puts "    Exit: 0"

    puts "\n=== SUCCESS ==="
    puts "URL: #{sandbox.preview_url}"
    puts "SSH: ssh deploy@#{sandbox.server_ip}"
    puts "Cleanup: rake rbrun:sandbox:destroy"
  end

  namespace :sandbox do
    desc "Destroy sandbox"
    task destroy: :environment do
      load_env!
      configure_sandbox!
      sandbox = Rbrun::Sandbox.find_by(slug: "a1b2c3")
      abort "No sandbox found" unless sandbox
      puts "Destroying #{sandbox.slug}..."
      sandbox.deprovision!
      puts "Done."
    end

    desc "SSH into sandbox"
    task ssh: :environment do
      load_env!
      configure_sandbox!
      sandbox = Rbrun::Sandbox.find_by(slug: "a1b2c3")
      abort "No sandbox found" unless sandbox
      abort "No IP" unless sandbox.server_ip
      exec "ssh -i /tmp/sandbox_key deploy@#{sandbox.server_ip}"
    end

    desc "Show command logs"
    task logs: :environment do
      sandbox = Rbrun::Sandbox.find_by(slug: "a1b2c3")
      abort "No sandbox" unless sandbox
      sandbox.command_executions.order(:id).each do |e|
        puts "\n--- #{e.category || e.command.truncate(50)} (exit: #{e.exit_code}) ---"
        e.command_logs.order(:line_number).limit(20).each { |l| puts l.content }
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Release: VM + K3s + Production
  # ─────────────────────────────────────────────────────────────

  desc "Deploy release and verify app"
  task release: :environment do
    load_env!
    configure_release!

    puts "=== Release Deploy ==="
    release = Rbrun::Release.create!
    puts "Release: #{release.id}"

    # Provision
    puts "\n[1] Provisioning K3s..."
    release.provision!
    puts "    IP: #{release.server_ip}"
    puts "    URL: #{release.url}"

    # Health check
    puts "\n[2] Health check..."
    wait_for_http!(release.url || "http://#{release.server_ip}:30080")

    puts "\n=== SUCCESS ==="
    puts "URL: #{release.url}"
    puts "SSH: ssh deploy@#{release.server_ip}"
    puts "Cleanup: rake rbrun:release:destroy"
  end

  namespace :release do
    desc "Destroy release"
    task destroy: :environment do
      load_env!
      configure_release!
      release = Rbrun::Release.last
      abort "No release found" unless release
      puts "Destroying release #{release.id}..."
      release.deprovision!
      release.mark_torn_down!
      puts "Done."
    end

    desc "SSH into release"
    task ssh: :environment do
      release = Rbrun::Release.deployed.last
      abort "No deployed release" unless release&.server_ip
      exec "ssh deploy@#{release.server_ip}"
    end

    desc "Show command logs"
    task logs: :environment do
      release = Rbrun::Release.last
      abort "No release" unless release
      release.command_executions.order(:id).each do |e|
        puts "\n--- #{e.category || e.command.truncate(50)} (exit: #{e.exit_code}) ---"
        e.command_logs.order(:line_number).limit(20).each { |l| puts l.content }
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────

  def load_env!
    require "dotenv"
    Dotenv.load(Rbrun::Engine.root.join(".env"))
  end

  def configure_sandbox!
    Rbrun.reset_configuration!
    Rbrun.configure do |c|
      c.compute(:hetzner) do |h|
        h.api_key = ENV.fetch("HETZNER_API_KEY")
        h.server_type = "cpx11"
        h.location = "ash"
      end

      c.git do |g|
        g.pat = ENV.fetch("GITHUB_TEST_PAT")
        g.repo = "benbonnet/dummy-rails"
      end

      c.cloudflare do |cf|
        cf.api_token = ENV.fetch("CLOUDFLARE_API_KEY")
        cf.account_id = ENV.fetch("CLOUDFLARE_ACCOUNT_ID")
        cf.domain = "rb.run"
      end

      c.claude do |cl|
        cl.auth_token = ENV.fetch("ANTHROPIC_API_KEY")
        cl.base_url = ENV.fetch("ZAI_BASE_URL", "https://api.anthropic.com")
      end

      c.database(:postgres)
      c.app { |a| a.process(:web) { |p| p.port = 3000 } }
      c.setup("bin/rails db:prepare")
      c.env(RAILS_ENV: "development", SECRET_KEY_BASE: "dev")
    end
  end

  def configure_release!
    Rbrun.reset_configuration!
    Rbrun.configure do |c|
      c.compute(:hetzner) do |h|
        h.api_key = ENV.fetch("HETZNER_API_KEY")
        h.server_type = { sandbox: "cpx11", release: "cpx21" }
        h.location = "ash"
      end

      c.git do |g|
        g.pat = ENV.fetch("GITHUB_TEST_PAT")
        g.repo = "benbonnet/dummy-rails"
      end

      c.cloudflare do |cf|
        cf.api_token = ENV.fetch("CLOUDFLARE_API_KEY")
        cf.account_id = ENV.fetch("CLOUDFLARE_ACCOUNT_ID")
        cf.domain = "rb.run"
      end

      c.database(:postgres) { |d| d.volume_size = 10 }

      c.service(:meilisearch) { |m| m.env = { MEILI_MASTER_KEY: ENV.fetch("MEILI_MASTER_KEY") } }

      c.app do |a|
        a.process(:web) do |p|
          p.port = 3000
          p.subdomain = "dummy"
        end
        a.process(:worker) do |p|
          p.command = "bin/jobs"
        end
      end

      c.env(
        RAILS_ENV: "production",
        RAILS_MASTER_KEY: ENV.fetch("DUMMY_RAILS_MASTER_KEY"),
        RAILS_SERVE_STATIC_FILES: "true",
        MEILI_MASTER_KEY: ENV.fetch("MEILI_MASTER_KEY")
      )
    end
  end

  def wait_for_http!(url, timeout: 120)
    require "faraday"
    conn = Faraday.new(url:, ssl: { verify: false }) { |f| f.options.timeout = 5 }
    (timeout / 5).times do |i|
      print "    Attempt #{i + 1}..."
      response = conn.get("/") rescue nil
      if response&.status && response.status < 500
        puts " OK (#{response.status})"
        return
      end
      puts " waiting..."
      sleep 5
    end
    raise "App not ready after #{timeout}s"
  end
end
