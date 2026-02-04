# Rbrun Engine Cleanup Plan

## Goal

Deploy app under HTTPS (Cloudflare) in a single command. Sandbox Claude Code for dev. Nothing more.

- **Sandbox**: VM → Docker Compose → Cloudflare tunnel → Claude Code
- **Release**: VM → K3s → Cloudflare tunnel

## Rules

- All commands through `CommandExecution` → `CommandLog`
- Self-hosted only
- No backup ops (sidecar handles it)
- No Kubernetes jobs

---

## Phase 1: Delete Dead Code

```bash
rm -rf lib/rbrun/databases/
rm -f lib/rbrun/provisioners.rb
rm -f lib/rbrun/provisioners/base.rb
rm -f lib/rbrun/configuration/production_config.rb
```

## Phase 2: Move Kubernetes Helpers

```bash
mv lib/rbrun/release/kubernetes/ lib/rbrun/kubernetes/
```

Update requires in files that reference old path.

## Phase 3: Restructure Provisioners

1. Rename `lib/rbrun/provisioners/vm.rb` → `lib/rbrun/provisioners/sandbox.rb`
2. Move `lib/rbrun/release/provisioner.rb` → `lib/rbrun/provisioners/release.rb`
3. Delete empty `lib/rbrun/release/` directory

## Phase 4: Fix Release Provisioner

In `lib/rbrun/provisioners/release.rb`:

1. Replace `release_config` → unified DSL (`Rbrun.configuration`)
2. Replace `Kubernetes::Manifests::*` → `Generators::K3s`
3. Remove backup code (`deploy_backup!`, `deploy_s3_secret!`, r2 methods)
4. Update namespace: `Rbrun::Provisioners::Release`

## Phase 5: Update Model References

`app/models/rbrun/sandbox/provisionable.rb`:

```ruby
# Before
@provisioner ||= Provisioners.for(self)

# After
@provisioner ||= Provisioners::Sandbox.new(self)
```

`app/models/rbrun/release/provisionable.rb`:

```ruby
# Before
@provisioner ||= Release::Provisioner.new(self)

# After
@provisioner ||= Provisioners::Release.new(self)
```

## Phase 6: Clean Naming

Remove from `lib/rbrun/naming.rb`:

- `snapshot` method (Daytona removed)
- `database_project` method (managed DBs removed)

## Phase 7: Update Kubernetes Namespaces

```ruby
# Before
module Rbrun::Release::Kubernetes

# After
module Rbrun::Kubernetes
```

Files:

- `lib/rbrun/kubernetes/kubectl.rb`
- `lib/rbrun/kubernetes/k3s_installer.rb`
- `lib/rbrun/kubernetes/docker_builder.rb`

## Phase 8: Update Requires

In autoload/requires:

- Remove `databases`
- Update `provisioners` paths
- Update `kubernetes` path

---

## Final Structure

```
lib/rbrun/
├── generators/
│   ├── compose.rb
│   └── k3s.rb
├── provisioners/
│   ├── sandbox.rb
│   └── release.rb
├── kubernetes/
│   ├── kubectl.rb
│   ├── k3s_installer.rb
│   └── docker_builder.rb
├── providers/
│   ├── hetzner/
│   ├── scaleway/
│   └── cloud_init.rb
├── cloudflare/
│   ├── client.rb
│   ├── config.rb
│   ├── r2.rb
│   └── worker.rb
├── ssh/
│   └── client.rb
├── configuration.rb
├── naming.rb
├── engine.rb
└── version.rb
```

## Deleted

- `lib/rbrun/databases/` (entire)
- `lib/rbrun/provisioners.rb` (factory)
- `lib/rbrun/provisioners/base.rb` (abstraction)
- `lib/rbrun/release/` (entire, after moves)
- `lib/rbrun/configuration/production_config.rb`

## Impact

~1,500 lines deleted, ~200 lines modified
