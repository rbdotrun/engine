# Rbrun Smoke Tests

## Overview

Smoke tests verify that the rbrun engine can provision sandboxes and run Claude Code commands end-to-end. They test real infrastructure (Hetzner VMs, Cloudflare tunnels, managed databases) with real credentials.

These are not unit tests. They create actual cloud resources, cost real money, and take several minutes to run. Use them to validate configuration changes, provider integrations, and deployment pipelines.

## Test Matrix

The smoke tests cover different provider combinations to ensure the modular configuration works across all supported setups:

| Test                      | Compute           | SQL Database         | Use Case                                |
| ------------------------- | ----------------- | -------------------- | --------------------------------------- |
| `smoke_test`              | Hetzner VM        | Self-hosted Postgres | Full control, cheapest for long-running |
| `smoke_test:hetzner_neon` | Hetzner VM        | Neon (managed)       | VM control + managed DB simplicity      |
| `smoke_test:daytona_neon` | Daytona (managed) | Neon (managed)       | Fully managed, fastest provisioning     |

### Why These Combinations?

**Hetzner + Self-hosted** (the default)

- User gets a full VM with Docker
- Database runs in a container alongside the app
- Best for: cost optimization, full SSH access, custom Docker setups
- Tradeoff: slower provisioning (~3-5 min), user manages DB backups

**Hetzner + Neon**

- User gets a full VM but database is managed
- App connects to Neon's serverless Postgres
- Best for: VM flexibility + database reliability
- Tradeoff: network latency to external DB, Neon costs

**Daytona + Neon**

- Both compute and database are managed services
- Fastest provisioning, least operational overhead
- Best for: quick iterations, ephemeral environments
- Tradeoff: less control, can't run arbitrary Docker, higher cost at scale

## What Each Test Does

### Phase 1: Configuration

```
[1/6] Configuring for matrix: hetzner_self_hosted
      Compute: Hetzner (cpx11 @ ash)
      Database: Self-hosted Postgres
      Repo: benbonnet/dummy-rails
```

The test loads credentials from `.env` and configures rbrun using the new modular DSL:

```ruby
Rbrun.configure do |c|
  c.compute(:hetzner) do |h|
    h.api_key = ENV["HETZNER_API_KEY"]
    h.server_type = "cpx11"
    h.location = "ash"
  end

  c.database(:sql, :neon) do |db|
    db.api_key = ENV["NEON_API_KEY"]
  end

  # ... cloudflare, git, etc.
end
```

### Phase 2: Provisioning

```
[2/6] Provisioning sandbox...
      [firewall] Creating sandbox-42 firewall
      [network] Creating sandbox-42 network
      [server] Creating sandbox-42 server (cpx11)
      [ssh_wait] Waiting for SSH...
      [apt_packages] Installing dependencies
      [docker] Starting Docker
      [nodejs] Installing Node.js 20
      [claude_code] Installing @anthropic-ai/claude-code
      [clone] Cloning benbonnet/dummy-rails
      [compose_setup] Starting Docker Compose
```

This phase:

1. Creates cloud resources (firewall, network, server)
2. Waits for VM to boot and SSH to be available
3. Installs system dependencies (Docker, Node.js, gh CLI)
4. Installs Claude Code globally
5. Clones the target repository
6. Starts the app via Docker Compose

For managed database tests (Neon), it also:

- Creates a Neon project
- Waits for the database to be ready
- Injects `DATABASE_URL` into the environment

### Phase 3: Tunnel Setup

```
[3/6] Setting up Cloudflare tunnel...
      Tunnel: sandbox-42
      DNS: sandbox-42.rb.run
      Preview URL: https://sandbox-42.rb.run
```

Creates a Cloudflare Tunnel so the sandbox is accessible via HTTPS without exposing ports directly.

### Phase 4: Health Check

```
[4/6] Waiting for app to respond...
      Attempt 1/30... 502
      Attempt 2/30... 502
      Attempt 3/30... 200 OK
```

Polls the preview URL until the Rails app responds with a non-5xx status code. This confirms:

- Docker Compose started successfully
- Rails booted without errors
- Database migrations ran
- Cloudflare tunnel is routing traffic

### Phase 5: Claude Code Verification

```
[5/6] Running Claude Code command...
      Command: "List the files in app/models and briefly describe what each one does"

      Output:
      Here are the files in app/models:
      - application_record.rb: Base class for all models
      - user.rb: User authentication and profile
      - post.rb: Blog post content and metadata

      Exit code: 0
```

This is the critical test. It runs an actual Claude Code command on the sandbox to verify:

- Claude Code is installed and executable
- API credentials are configured (ANTHROPIC_API_KEY)
- The sandbox can make outbound HTTPS requests
- Claude can read and analyze the codebase

If this step fails, the sandbox might be "running" but not actually usable for its intended purpose.

### Phase 6: Report

```
[6/6] SUCCESS!

      Matrix: hetzner_self_hosted
      Sandbox: smoke-hetzner-self-hosted (id: 42)
      URL: https://sandbox-42.rb.run
      State: running

      Provisioning time: 4m 32s
      Claude Code: working

      Cleanup: rake rbrun:cleanup[42]
```

## Running the Tests

### Prerequisites

1. **Credentials in `.env`** (at engine root):

```bash
# Compute
HETZNER_API_KEY=xxx
DAYTONA_API_KEY=xxx

# Database
NEON_API_KEY=xxx

# Cloudflare
CLOUDFLARE_API_KEY=xxx
CLOUDFLARE_ACCOUNT_ID=xxx

# Git
GITHUB_TEST_PAT=xxx

# Claude (for the sandbox to use)
ANTHROPIC_API_KEY=xxx
```

2. **Test repository** configured in the rake task (default: `benbonnet/dummy-rails`)
   - Must have a `docker-compose.dev.yml`
   - Must be a Rails app that boots successfully

### Commands

```bash
# Run default test (Hetzner + self-hosted)
rake rbrun:smoke_test

# Run specific matrix
rake rbrun:smoke_test:hetzner_neon
rake rbrun:smoke_test:daytona_neon

# Run all matrices
rake rbrun:smoke_test:all

# Cleanup after testing
rake rbrun:cleanup[SANDBOX_ID]
```

### Expected Duration

| Matrix              | Provisioning | Total   |
| ------------------- | ------------ | ------- |
| hetzner_self_hosted | 4-6 min      | 5-8 min |
| hetzner_neon        | 4-6 min      | 5-8 min |
| daytona_neon        | 1-2 min      | 2-4 min |

### Expected Cost

| Matrix              | Per Run | Notes                            |
| ------------------- | ------- | -------------------------------- |
| hetzner_self_hosted | ~$0.01  | cpx11 is €4.50/mo, billed hourly |
| hetzner_neon        | ~$0.02  | Hetzner + Neon free tier         |
| daytona_neon        | ~$0.05  | Daytona sandbox pricing          |

**Always run `rake rbrun:cleanup[ID]` after testing** to avoid accumulating charges.

## Failure Modes

### Configuration Errors

```
ERROR: Unknown compute provider: hetzner
```

Check that the configuration DSL matches the new modular format.

### Credential Errors

```
ERROR: Hetzner API error: 401 Unauthorized
```

Verify `.env` has valid credentials. Test with:

```bash
curl -H "Authorization: Bearer $HETZNER_API_KEY" https://api.hetzner.cloud/v1/servers
```

### Provisioning Timeout

```
ERROR: Server did not become ready after 60 attempts
```

Check Hetzner console for server status. May be capacity issues in the selected region.

### SSH Connection Failed

```
ERROR: SSH connection refused
```

Server booted but SSH isn't ready. Usually resolves with retry. Check cloud-init logs if persistent.

### Docker Compose Failed

```
ERROR: Container sandbox-42-web exited with code 1
```

App failed to start. SSH into the sandbox and check logs:

```bash
ssh deploy@<ip> "cd /home/deploy/workspace && docker compose logs"
```

### Claude Code Failed

```
ERROR: Claude Code command failed with exit code 1
Output: "ANTHROPIC_API_KEY not set"
```

The sandbox doesn't have Claude API credentials. Check that `ANTHROPIC_API_KEY` is being injected into the environment.

### Database Connection Failed

```
ERROR: PG::ConnectionBad: could not connect to server
```

For Neon: check that the project was created and `DATABASE_URL` was set.
For self-hosted: check that the `db` container is running.

## Interpreting Results

### All Green

```
✓ smoke_test (hetzner_self_hosted): 5m 12s
✓ smoke_test:hetzner_neon: 5m 34s
✓ smoke_test:daytona_neon: 2m 45s
```

The modular configuration is working correctly across all provider combinations.

### Partial Failure

```
✓ smoke_test (hetzner_self_hosted): 5m 12s
✗ smoke_test:hetzner_neon: FAILED (Neon API error)
✓ smoke_test:daytona_neon: 2m 45s
```

The Neon integration has an issue. Check:

- Neon API key validity
- Neon client implementation
- Database configuration DSL

### Claude Code Failure Only

```
✓ Provisioning: OK
✓ Health check: OK
✗ Claude Code: FAILED
```

The sandbox runs but Claude Code doesn't work. Check:

- Claude Code installation step in provisioning
- ANTHROPIC_API_KEY injection
- Outbound HTTPS from sandbox

## Adding New Matrices

To add a new provider combination:

1. Add configuration helper in `rbrun_tasks.rake`:

```ruby
def configure_scaleway_turso!
  Rbrun.configure do |c|
    c.compute(:scaleway) do |s|
      s.api_key = ENV.fetch("SCALEWAY_API_KEY")
      s.project_id = ENV.fetch("SCALEWAY_PROJECT_ID")
    end

    c.database(:sql, :turso) do |db|
      db.api_token = ENV.fetch("TURSO_API_TOKEN")
      db.organization = ENV.fetch("TURSO_ORG")
    end

    # ... rest of config
  end
end
```

2. Add rake task:

```ruby
desc "Smoke test: Scaleway + Turso"
task "smoke_test:scaleway_turso": :environment do
  run_smoke_test(:scaleway_turso)
end
```

3. Add to matrix switch:

```ruby
when :scaleway_turso
  configure_scaleway_turso!
```

4. Update this documentation with expected duration and cost.

## CI Integration

For automated testing in CI:

```yaml
# .github/workflows/smoke.yml
name: Smoke Tests
on:
  schedule:
    - cron: "0 6 * * *" # Daily at 6am UTC
  workflow_dispatch:

jobs:
  smoke:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test: [smoke_test, smoke_test:hetzner_neon, smoke_test:daytona_neon]
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
      - run: bundle install
      - run: bundle exec rake rbrun:${{ matrix.test }}
        env:
          HETZNER_API_KEY: ${{ secrets.HETZNER_API_KEY }}
          NEON_API_KEY: ${{ secrets.NEON_API_KEY }}
          # ... other secrets
      - run: bundle exec rake rbrun:cleanup[${{ env.SANDBOX_ID }}]
        if: always()
```

**Important**: Always cleanup in CI, even on failure, to avoid orphaned resources.
