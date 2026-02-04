# K3s Resource Management

Single-node safety: protect the database at all costs. When memory pressure hits, app pods die first—database keeps running.

## The Rules

1. **CPU requests, NEVER CPU limits** - Requests give scheduling weight. Limits cause invisible throttling.
2. **Memory limits for safety** - OOM kills are visible and debuggable. Throttling is not.
3. **Priority classes determine eviction order** - Higher value = harder to kill.
4. **Database is untouchable** - Priority 1,000,000,000 (max safe value).
5. **Apps are expendable** - Priority 1,000. They die first, restart fast.

## Priority Classes

Deployed automatically during K3s install (`K3sInstaller#deploy_priority_classes!`):

| Name | Value | globalDefault | Purpose |
|------|-------|---------------|---------|
| `database-critical` | 1,000,000,000 | false | Postgres, Redis (as db) - never evict |
| `platform` | 100,000 | false | Cloudflared, meilisearch, ingress - evict after apps |
| `app` | 1,000 | **true** | User workloads - evict first |

## Resource Profiles

Defined in `Kubernetes::Resources::PROFILES`:

| Profile | Memory Request | Memory Limit | CPU Request | CPU Limit |
|---------|----------------|--------------|-------------|-----------|
| `:database` | 512Mi | 1536Mi | 250m | **NONE** |
| `:platform` | 64Mi | 256Mi | 50m | NONE |
| `:small` | 128Mi | 256Mi | 100m | NONE |
| `:medium` | 256Mi | 512Mi | 200m | NONE |
| `:large` | 512Mi | 1Gi | 300m | NONE |

Default app size: `:small`

## Workload Assignment

| Workload Type | Priority Class | Resource Profile |
|---------------|----------------|------------------|
| Postgres | `database-critical` | `:database` |
| Redis (as database) | `database-critical` | `:database` |
| Meilisearch | `platform` | `:platform` |
| Cloudflared | `platform` | `:platform` |
| App processes (web, worker) | `app` | `:small` |

## 8GB Node Math

```
Total RAM:                 8Gi
System reserved (OS):      ~500Mi
K3s overhead:              ~800Mi
Eviction threshold:        500Mi (kubelet starts killing pods)
───────────────────────────────────
Schedulable:               ~6.2Gi

Database (guaranteed):     512Mi request
Platform services:         ~128Mi request
───────────────────────────────────
Available for apps:        ~5.5Gi
```

With `:small` profile (128Mi request), you can schedule ~40 app pods. Realistically 10-20 with headroom for bursting.

## Eviction Order Under Memory Pressure

When the node runs low on memory, kubelet evicts in this order:

1. Pods using more memory than requested (greedy pods first)
2. Lower priority pods before higher priority
3. Newer pods before older pods (among same priority)

App pods (priority 1000) get evicted long before database (priority 1B) is touched.

## Files

```
lib/rbrun/kubernetes/resources.rb      # profiles, priorities, manifests
lib/rbrun/kubernetes/k3s_installer.rb  # deploys priority classes at setup
lib/rbrun/generators/k3s.rb            # injects resources into containers
```

## Future: Size Overrides

The structure supports per-process size configuration:

```ruby
# Not yet implemented
app.process(:web) { |p| p.size = :medium }
```

Wire by reading `process.size` in `Generators::K3s#process_manifests` and passing to `Resources.for(size)`.
