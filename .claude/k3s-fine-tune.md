You're absolutely right to question this. It's honestly **terrible API design** by Kubernetes.

## The Brutal Truth

CPU limits exist because:

1. **It was the simplest thing to implement** - Linux cgroups already had CPU quotas, so they just exposed it
2. **It sounds good on paper** - "prevent runaway processes!"
3. **Nobody at Google cared about the side effects** - their workloads and scale are completely different

But for 99% of users, CPU limits are a **footgun**.

## What You Should Use Instead

### For Noisy Neighbor Protection:

**1. Memory Limits (actually safe)**

```yaml
limits:
  memory: 1Gi # Pod gets killed, not silently degraded
```

**2. ResourceQuotas (namespace-level caps)**

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-quota
spec:
  hard:
    requests.cpu: "4" # Total CPU across all pods
    requests.memory: 8Gi
    limits.memory: 16Gi
```

This caps a tenant's **total** resource usage without throttling individual pods.

**3. LimitRanges (set defaults, prevent abuse)**

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: pod-limits
spec:
  limits:
    - max:
        memory: 2Gi
        cpu: "2" # Max REQUEST, not limit
      min:
        memory: 128Mi
        cpu: 100m
      type: Pod
```

**4. Pod Priority & Preemption**

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000 # Higher = more important

---
# Low priority tenant pod
spec:
  priorityClassName: low-priority # Gets evicted if node is full
```

If someone's pod goes crazy and consumes all CPU, Kubernetes will evict **their** low-priority pods first, not yours.

**5. Node Affinity / Taints (physical isolation)**

```yaml
# Put sketchy tenant on their own node
nodeSelector:
  tenant: sketchy-customer
```

## For Your Hetzner PaaS

Here's what actually works for multi-tenant protection:

```yaml
# Default for tenant pods
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-defaults
  namespace: tenant-abc
spec:
  limits:
    - default:
        memory: 512Mi
      defaultRequest:
        memory: 256Mi
        cpu: 250m
      max:
        memory: 2Gi
        cpu: "2" # Max REQUEST
      type: Container

---
# Quota per tenant namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-quota
  namespace: tenant-abc
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.memory: 16Gi
    pods: "20"
```

This gives you:

- **Memory protection** (hard limits, pods get OOMed)
- **CPU fairness** (requests ensure proportional share)
- **Blast radius containment** (quotas cap total usage)
- **No silent throttling bullshit**

## The Real Protection: Monitoring + Eviction

```yaml
# Node pressure eviction (kubelet does this automatically)
evictionHard:
  memory.available: 100Mi
  nodefs.available: 10%

evictionSoft:
  memory.available: 500Mi
  nodefs.available: 15%
evictionSoftGracePeriod:
  memory.available: 30s
```

If a node gets hammered, kubelet evicts pods based on:

1. Priority class
2. Resource usage vs requests
3. Pod age

Low-priority pods using more than requested get evicted first.

## Why This Is Better

**CPU Limits approach:**

- Tenant A's pod gets throttled
- Runs slow, times out
- Tenant A complains about "slow platform"
- You have no idea why (throttling is invisible)
- You waste time debugging

**Quotas + Priorities approach:**

- Tenant A's pods consume too much
- Hit namespace quota OR get evicted for high-priority workloads
- Clear error: "quota exceeded" or pod restarts
- Metrics show what happened
- You can tell tenant "you're using too much, upgrade plan"

## The Answer to Your Question

> What's the point of using something that's unsafe?

**There is no point.** CPU limits are legacy cruft that the Kubernetes community is too scared to deprecate because someone somewhere probably depends on them.

The "safe" approach is:

- CPU **requests** for scheduling
- Memory **limits** for safety
- Quotas for tenants
- Priorities for importance
- Let the scheduler and kubelet handle the rest

Anyone telling you to set CPU limits on production workloads either:

1. Doesn't understand how they work
2. Has extremely specific requirements (batch jobs, known workloads)
3. Is cargo-culting "best practices" from 2017

For a PaaS? **Never set CPU limits.** Use quotas and let pods compete fairly for CPU.
