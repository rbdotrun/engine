# Cloudflare Worker Widget Injection - rbrun Implementation

## Goal

Inject a simple "It Works!" popup into sandbox preview apps. **One worker per sandbox**, deployed alongside the tunnel.

---

## Current Flow (what we have)

```
provision!
  └── setup_compose_tunnel!
        ├── find_or_create_tunnel(sandbox-{id})
        ├── configure_tunnel_ingress
        ├── ensure_dns_record(sandbox-{id}.rb.run)
        └── start_compose_tunnel_container!

Traffic: User → sandbox-{id}.rb.run → Cloudflare Edge → Tunnel → Server → App
```

---

## New Flow (what we add)

```
provision!
  └── setup_compose_tunnel!
        ├── find_or_create_tunnel(sandbox-{id})
        ├── configure_tunnel_ingress
        ├── ensure_dns_record(sandbox-{id}.rb.run)
        ├── NEW: deploy_worker(rbrun-widget-{id})
        ├── NEW: create_worker_route(sandbox-{id}.rb.run/*)
        └── start_compose_tunnel_container!

Traffic: User → sandbox-{id}.rb.run → Worker (injects popup) → Tunnel → Server → App
```

---

## Implementation

### 1. Static Worker Script (inline)

Minimal worker - injects popup into every HTML response:

```javascript
export default {
  async fetch(request) {
    const response = await fetch(request);
    const contentType = response.headers.get("content-type") || "";

    if (!contentType.includes("text/html")) {
      return response;
    }

    return new HTMLRewriter()
      .on("body", {
        element(el) {
          el.append(
            `
<script>
(function(){
  var d = document.createElement('div');
  d.style.cssText = 'position:fixed;bottom:20px;right:20px;background:#10b981;color:white;padding:12px 20px;border-radius:24px;z-index:99999;font-family:system-ui;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.15);';
  d.textContent = '✓ rbrun';
  d.onclick = function() { alert('Sandbox: SANDBOX_ID'); };
  document.body.appendChild(d);
})();
</script>
          `,
            { html: true },
          );
        },
      })
      .transform(response);
  },
};
```

### 2. CloudflareClient - Add Worker Methods

```ruby
# Worker name follows same pattern as tunnels: per-sandbox
def worker_name(sandbox_id)
  "rbrun-widget-#{sandbox_id}"
end

def deploy_worker(sandbox_id)
  script = worker_script(sandbox_id)
  name = worker_name(sandbox_id)

  # Multipart form upload (required by CF API)
  uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{name}")

  boundary = "----RbrunBoundary#{SecureRandom.hex(8)}"
  metadata = { main_module: "worker.js", compatibility_date: "2024-01-01" }

  body = build_worker_multipart(boundary, metadata, script)
  put_multipart(uri, body, boundary)
end

def create_worker_route(zone_id, sandbox_id, domain)
  pattern = "sandbox-#{sandbox_id}.#{domain}/*"
  post("/zones/#{zone_id}/workers/routes", {
    pattern: pattern,
    script: worker_name(sandbox_id)
  })
end

def delete_worker(sandbox_id)
  delete("/accounts/#{account_id}/workers/scripts/#{worker_name(sandbox_id)}")
end

private

def worker_script(sandbox_id)
  # Inline script with sandbox_id baked in
  <<~JS
    export default {
      async fetch(request) {
        const response = await fetch(request);
        const ct = response.headers.get('content-type') || '';
        if (!ct.includes('text/html')) return response;

        return new HTMLRewriter()
          .on('body', {
            element(el) {
              el.append('<script>(function(){var d=document.createElement("div");d.style.cssText="position:fixed;bottom:20px;right:20px;background:#10b981;color:white;padding:12px 20px;border-radius:24px;z-index:99999;font-family:system-ui;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.15);";d.textContent="✓ rbrun";d.onclick=function(){alert("Sandbox: #{sandbox_id}")};document.body.appendChild(d)})();</script>', { html: true });
            }
          })
          .transform(response);
      }
    };
  JS
end

def build_worker_multipart(boundary, metadata, script)
  parts = []
  parts << "--#{boundary}\r\n"
  parts << "Content-Disposition: form-data; name=\"metadata\"\r\n"
  parts << "Content-Type: application/json\r\n\r\n"
  parts << metadata.to_json
  parts << "\r\n--#{boundary}\r\n"
  parts << "Content-Disposition: form-data; name=\"worker.js\"; filename=\"worker.js\"\r\n"
  parts << "Content-Type: application/javascript+module\r\n\r\n"
  parts << script
  parts << "\r\n--#{boundary}--\r\n"
  parts.join
end
```

### 3. Previewable - Wire It Up

In `setup_compose_tunnel!`, after DNS setup:

```ruby
# Deploy worker for this sandbox
deploy_sandbox_worker!
```

Add method:

```ruby
def deploy_sandbox_worker!
  cloudflare_client.deploy_worker(id)
  cloudflare_client.create_worker_route(cloudflare_zone_id, id, preview_zone)
  Rails.logger.info "[Rbrun::Sandbox] Worker deployed: rbrun-widget-#{id}"
rescue => e
  Rails.logger.warn "[Rbrun::Sandbox] Worker deploy failed (non-fatal): #{e.message}"
end
```

In `delete_compose_tunnel!`, add cleanup:

```ruby
# Delete worker
begin
  cloudflare_client.delete_worker(id)
rescue CloudflareClient::NotFoundError
  # Already gone
end
```

---

## Files to Modify

| File                                      | Change                                                      |
| ----------------------------------------- | ----------------------------------------------------------- |
| `app/clients/rbrun/cloudflare_client.rb`  | Add `deploy_worker`, `create_worker_route`, `delete_worker` |
| `app/models/rbrun/sandbox/previewable.rb` | Call worker methods in setup/delete                         |

---

## Test

```bash
# After sandbox deployed
curl -s https://sandbox-4.rb.run | grep "rbrun"
# Should see injected script
```

Visit https://sandbox-4.rb.run - green "✓ rbrun" bubble in bottom-right.

---

## Cleanup

Workers are deleted with sandbox (in `delete_compose_tunnel!`).

---

## Later

- External widget.js served from Rails
- JWT auth token
- WebSocket chat interface
- Pass sandbox context to AI
