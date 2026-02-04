# frozen_string_literal: true

require "dotenv"
Dotenv.load(Rbrun::Engine.root.join(".env"))

Rbrun.configure do |c|
  c.compute(:hetzner) do |com|
    com.api_key = ENV["HETZNER_API_KEY"]
  end

  c.git do |g|
    g.pat = ENV["GITHUB_TEST_PAT"]
    g.repo = "benbonnet/dummy-rails"
  end

  c.cloudflare do |cf|
    cf.api_token = ENV["CLOUDFLARE_API_KEY"]
    cf.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
    cf.domain = "rb.run"
  end

  c.claude do |cl|
    cl.auth_token = ENV["ZAI_AUTH_TOKEN"]
    cl.base_url = ENV["ZAI_BASE_URL"]
  end

  c.database(:postgres)

  c.app do |a|
    a.process(:web) do |p|
      p.command = "bin/rails server"
      p.port = 3000
    end
  end

  c.setup("bin/rails db:prepare")
  c.env(
    RAILS_ENV: "development",
    SECRET_KEY_BASE: "dev-secret"
  )
end
