# Rbrun

Ephemeral cloud development environments for Rails. Spin up isolated Hetzner VMs with your repo, expose them publicly via Cloudflare Tunnels.

## Installation

```ruby
# Gemfile
gem "rbrun"
```

```bash
bundle install
bin/rails rbrun:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb
mount Rbrun::Engine, at: "/rbrun"
```

## Configuration

```ruby
# config/initializers/rbrun.rb
Rbrun.configure do |c|
  c.compute do |com|
    com.provider = "hetzner"
    com.api_key = ENV["HETZNER_API_KEY"]
    com.server_type = "cpx21"
    com.location = "nbg1"
  end

  c.git do |g|
    g.pat = ENV["GITHUB_TOKEN"]
    g.repo = "owner/my-rails-app"
    g.username = "deploy-bot"
    g.email = "bot@myapp.dev"
  end

  c.cloudflare do |cf|
    cf.api_key = ENV["CLOUDFLARE_API_KEY"]
    cf.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
    cf.domain = "myapp.dev"
  end

  c.compose_file = "docker-compose.dev.yml"

  c.setup("bundle install", "rails db:prepare", "yarn install")

  c.env(
    RAILS_ENV: "development",
    DATABASE_URL: "postgres://postgres:postgres@db:5432/app"
  )

  c.claude do |cl|
    cl.auth_token = ENV["ANTHROPIC_API_KEY"]
  end
end
```

---

## Reference

### `compute` (required)

| Option        | Default   | Description              |
| ------------- | --------- | ------------------------ |
| `provider`    | `hetzner` | `"hetzner"` only for now |
| `api_key`     | -         | Hetzner API token        |
| `server_type` | `cpx11`   | VM size                  |
| `location`    | `ash`     | Datacenter               |

### `git` (required)

| Option     | Default             | Description                  |
| ---------- | ------------------- | ---------------------------- |
| `pat`      | -                   | GitHub Personal Access Token |
| `repo`     | -                   | `owner/repo` format          |
| `username` | `rbrun`             | Git author name              |
| `email`    | `sandbox@rbrun.dev` | Git author email             |

### `cloudflare` (optional)

Enables public URLs at `sandbox-{id}.{domain}`. Omit block for private-only.

| Option       | Description             |
| ------------ | ----------------------- |
| `api_key`    | Cloudflare API token    |
| `account_id` | Cloudflare account ID   |
| `domain`     | Base domain for tunnels |

### `claude` (optional)

Enables Claude AI integration for sandbox interactions.

| Option       | Default                      | Description            |
| ------------ | ---------------------------- | ---------------------- |
| `auth_token` | -                            | Anthropic API key      |
| `base_url`   | `https://api.anthropic.com`  | Anthropic API base URL |

```ruby
c.claude do |cl|
  cl.auth_token = ENV["ANTHROPIC_API_KEY"]
end
```

### `compose_file` (required)

Path to docker-compose file in your repo.

```ruby
c.compose_file = "docker-compose.dev.yml"
```

### `setup` (optional)

Commands run inside `web` container after compose starts.

```ruby
c.setup("bundle install", "rails db:prepare")
```

### `env` (optional)

Environment variables written to `.env`.

```ruby
c.env(RAILS_ENV: "development", SECRET_KEY_BASE: "dev-key")
```

---

## Usage

Visit `/rbrun`. Click **Launch Sandbox**.

Each sandbox:

1. Provisions Hetzner VM
2. Clones repo + creates branch
3. Runs docker compose
4. Executes setup commands
5. Exposes via Cloudflare (if configured)

---

## Example docker-compose.dev.yml

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

  web:
    build: .
    command: bin/dev
    ports:
      - "3000:3000"
    volumes:
      - .:/app
    depends_on:
      - db

volumes:
  postgres_data:
```

## Development

### Stimulus Controllers (Isolated Engine Pattern)

The engine uses its own isolated Stimulus application, separate from the host app.

**Structure:**
```
app/javascript/rbrun/
├── application.js                    # Entry point: imports controllers
└── controllers/
    ├── application.js                # Stimulus Application.start()
    ├── index.js                      # eagerLoadControllersFrom
    └── *_controller.js               # Controllers
```

**Importmap** (`config/importmap.rb`): Pins are namespaced under `rbrun/controllers`. Controllers register as `rbrun--{name}` (e.g., `rbrun--infinite-scroll`).

**Helper**: `rbrun_importmap_tags` renders the engine's own importmap in the layout. Host app's importmap is not used.

## License

MIT
