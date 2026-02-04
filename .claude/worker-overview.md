# Blueprint: Cloudflare Worker Widget Injection for Sandbox Previews

## Context

This document describes how to inject a chat widget into sandbox preview applications deployed on Hetzner via our PaaS platform. The widget enables AI-assisted navigation and interaction within the deployed user app.

### Current Deployment Workflow

```
1. User triggers deployment
2. Clone repo on Hetzner server
3. Start app using docker-compose
4. Setup Cloudflare DNS (via API)
5. Setup Cloudflare Tunnel (via API)
6. Start tunnel in k3s
7. Traffic flows: Cloudflare Edge → Tunnel → k3s → nginx ingress → svc → app pod
```

### Goal

Inject a widget script into every HTML response served by sandbox preview apps. The widget displays an "It Works" bubble (MVP), later evolving into a full AI chat interface.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Cloudflare Edge                               │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Cloudflare Worker                         │    │
│  │  1. Intercept request                                        │    │
│  │  2. Fetch from origin (via tunnel)                          │    │
│  │  3. If HTML response → inject widget script via HTMLRewriter │    │
│  │  4. Return modified response                                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Cloudflare Tunnel                               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    k3s Cluster (Hetzner)                            │
│  nginx ingress → service → user app pod                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: Create the Cloudflare Worker Script

The Worker intercepts HTML responses and injects the widget script using `HTMLRewriter`.

**Worker Script (`widget-injector.js`):**

```javascript
export default {
  async fetch(request, env, ctx) {
    // Fetch from origin (goes through tunnel)
    const response = await fetch(request);

    // Only transform HTML responses
    const contentType = response.headers.get("content-type") || "";
    if (!contentType.includes("text/html")) {
      return response;
    }

    // Extract project context from hostname
    // e.g., "my-app-abc123.previews.yourplatform.com" → "abc123"
    const url = new URL(request.url);
    const hostname = url.hostname;
    const projectId = extractProjectId(hostname); // implement based on your subdomain pattern

    // Generate signed JWT token for widget auth
    const token = await generateToken(projectId, env.JWT_SECRET);

    // Inject widget script into HTML
    return new HTMLRewriter()
      .on("body", new WidgetInjector(token, env.WIDGET_URL, projectId))
      .transform(response);
  },
};

class WidgetInjector {
  constructor(token, widgetUrl, projectId) {
    this.token = token;
    this.widgetUrl = widgetUrl;
    this.projectId = projectId;
  }

  element(element) {
    const script = `
<script>
(function(){
  var s = document.createElement('script');
  s.src = '${this.widgetUrl}';
  s.dataset.token = '${this.token}';
  s.dataset.projectId = '${this.projectId}';
  document.body.appendChild(s);
})();
</script>`;
    element.append(script, { html: true });
  }
}

function extractProjectId(hostname) {
  // Adjust regex based on your subdomain pattern
  // Example: "myapp-abc123.previews.platform.com" → "abc123"
  const match = hostname.match(/^[\w-]+-(\w+)\.previews\./);
  return match ? match[1] : "unknown";
}

async function generateToken(projectId, secret) {
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    projectId: projectId,
    exp: Math.floor(Date.now() / 1000) + 3600, // 1 hour
    iat: Math.floor(Date.now() / 1000),
  };

  const encoder = new TextEncoder();
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, "");
  const payloadB64 = btoa(JSON.stringify(payload)).replace(/=/g, "");
  const data = `${headerB64}.${payloadB64}`;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  const signatureB64 = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  ).replace(/=/g, "");

  return `${data}.${signatureB64}`;
}
```

---

### Step 2: Deploy Worker via Cloudflare API

#### API Endpoint

```
PUT https://api.cloudflare.com/client/v4/accounts/{account_id}/workers/scripts/{script_name}
```

#### Required Headers

```
Authorization: Bearer {API_TOKEN}
Content-Type: multipart/form-data
```

#### API Token Permissions

Create an API token at https://dash.cloudflare.com/profile/api-tokens with:

- **Workers Scripts (Edit)** permission

#### Request Format (multipart/form-data)

The Worker upload uses multipart form data with:

1. **metadata** part: JSON configuration
2. **script** part: The JavaScript code

**Example using curl:**

```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/widget-injector" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -F 'metadata={"main_module": "widget-injector.js", "bindings": [{"type": "secret_text", "name": "JWT_SECRET", "text": "your-secret-key"}, {"type": "plain_text", "name": "WIDGET_URL", "text": "https://chat.yourplatform.com/widget.js"}], "compatibility_date": "2024-01-01"};type=application/json' \
  -F 'widget-injector.js=@widget-injector.js;type=application/javascript+module'
```

**Example using Node.js/fetch:**

```javascript
async function deployWorker(
  accountId,
  apiToken,
  scriptName,
  scriptContent,
  secrets,
) {
  const metadata = {
    main_module: `${scriptName}.js`,
    bindings: [
      { type: "secret_text", name: "JWT_SECRET", text: secrets.jwtSecret },
      { type: "plain_text", name: "WIDGET_URL", text: secrets.widgetUrl },
    ],
    compatibility_date: "2024-01-01",
  };

  const formData = new FormData();
  formData.append("metadata", JSON.stringify(metadata), {
    contentType: "application/json",
  });
  formData.append(`${scriptName}.js`, scriptContent, {
    contentType: "application/javascript+module",
  });

  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/scripts/${scriptName}`,
    {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${apiToken}`,
      },
      body: formData,
    },
  );

  return response.json();
}
```

#### Documentation Reference

- Upload Worker: https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/
- Multipart metadata format: https://developers.cloudflare.com/workers/configuration/multipart-upload-metadata/

---

### Step 3: Create Worker Route

After deploying the Worker, create a route to trigger it for preview subdomains.

#### API Endpoint

```
POST https://api.cloudflare.com/client/v4/zones/{zone_id}/workers/routes
```

#### Request Body

```json
{
  "pattern": "*.previews.yourplatform.com/*",
  "script": "widget-injector"
}
```

**Example using curl:**

```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/workers/routes" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "*.previews.yourplatform.com/*",
    "script": "widget-injector"
  }'
```

**Example using Node.js/fetch:**

```javascript
async function createWorkerRoute(zoneId, apiToken, pattern, scriptName) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/zones/${zoneId}/workers/routes`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        pattern: pattern,
        script: scriptName,
      }),
    },
  );

  return response.json();
}

// Usage
await createWorkerRoute(
  ZONE_ID,
  CF_API_TOKEN,
  "*.previews.yourplatform.com/*",
  "widget-injector",
);
```

#### Documentation Reference

- Routes overview: https://developers.cloudflare.com/workers/configuration/routing/routes/
- Create Route API: https://developers.cloudflare.com/api/resources/workers/subresources/routes/methods/create/

---

### Step 4: Widget Script (Served from Rails)

The injected script loads this widget from your Rails app.

**`public/widget.js` (or served via Rails controller):**

```javascript
(function () {
  const token = document.currentScript.dataset.token;
  const projectId = document.currentScript.dataset.projectId;

  // Styles
  const style = document.createElement("style");
  style.textContent = `
    .platform-widget {
      position: fixed;
      bottom: 20px;
      right: 20px;
      z-index: 99999;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    .platform-widget-bubble {
      background: #10b981;
      color: white;
      padding: 12px 20px;
      border-radius: 24px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      cursor: pointer;
      font-size: 14px;
      font-weight: 500;
      transition: transform 0.2s, box-shadow 0.2s;
    }
    .platform-widget-bubble:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 16px rgba(0,0,0,0.2);
    }
  `;
  document.head.appendChild(style);

  // Widget
  const widget = document.createElement("div");
  widget.className = "platform-widget";
  widget.innerHTML = `
    <div class="platform-widget-bubble">
      ✓ It Works! (Project: ${projectId})
    </div>
  `;
  document.body.appendChild(widget);

  // Log for debugging
  console.log("[Platform Widget] Loaded", { projectId, tokenPresent: !!token });

  // Click handler (placeholder for future chat functionality)
  widget
    .querySelector(".platform-widget-bubble")
    .addEventListener("click", function () {
      alert(
        "Widget clicked! Project: " +
          projectId +
          "\nToken: " +
          (token ? "Present" : "Missing"),
      );
    });
})();
```

---

## Integration with Deployment Workflow

### Updated Workflow

```ruby
# In your deployment service/job

class SandboxDeploymentService
  def deploy(sandbox)
    # 1. Existing steps...
    clone_repository(sandbox)
    start_with_compose(sandbox)

    # 2. Setup Cloudflare DNS
    setup_dns(sandbox)

    # 3. Setup Cloudflare Tunnel
    setup_tunnel(sandbox)

    # 4. NEW: Ensure Worker exists and route is configured
    ensure_widget_injection(sandbox)

    # 5. Start tunnel
    start_tunnel(sandbox)
  end

  private

  def ensure_widget_injection(sandbox)
    # Deploy worker if not exists (idempotent - PUT creates or updates)
    CloudflareWorkerService.deploy_widget_injector

    # Route is wildcard-based, so typically set once
    # But can verify it exists
    CloudflareWorkerService.ensure_route_exists
  end
end
```

### Cloudflare Worker Service

```ruby
# app/services/cloudflare_worker_service.rb

class CloudflareWorkerService
  ACCOUNT_ID = ENV['CLOUDFLARE_ACCOUNT_ID']
  ZONE_ID = ENV['CLOUDFLARE_ZONE_ID']
  API_TOKEN = ENV['CLOUDFLARE_API_TOKEN']

  SCRIPT_NAME = 'widget-injector'
  ROUTE_PATTERN = '*.previews.yourplatform.com/*'

  class << self
    def deploy_widget_injector
      script_content = build_worker_script

      uri = URI("https://api.cloudflare.com/client/v4/accounts/#{ACCOUNT_ID}/workers/scripts/#{SCRIPT_NAME}")

      # Build multipart form
      boundary = "----FormBoundary#{SecureRandom.hex(8)}"

      metadata = {
        main_module: "#{SCRIPT_NAME}.js",
        bindings: [
          { type: 'secret_text', name: 'JWT_SECRET', text: ENV['JWT_SECRET'] },
          { type: 'plain_text', name: 'WIDGET_URL', text: ENV['WIDGET_URL'] }
        ],
        compatibility_date: '2024-01-01'
      }

      body = build_multipart_body(boundary, metadata, script_content)

      request = Net::HTTP::Put.new(uri)
      request['Authorization'] = "Bearer #{API_TOKEN}"
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      JSON.parse(response.body)
    end

    def ensure_route_exists
      # List existing routes
      routes = list_routes

      # Check if our route exists
      existing = routes.dig('result')&.find { |r| r['pattern'] == ROUTE_PATTERN }

      return existing if existing

      # Create route if not exists
      create_route
    end

    private

    def build_worker_script
      # Can be loaded from file or defined inline
      File.read(Rails.root.join('lib', 'cloudflare', 'widget-injector.js'))
    end

    def build_multipart_body(boundary, metadata, script_content)
      body = ""

      # Metadata part
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"metadata\"\r\n"
      body << "Content-Type: application/json\r\n\r\n"
      body << metadata.to_json
      body << "\r\n"

      # Script part
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{SCRIPT_NAME}.js\"; filename=\"#{SCRIPT_NAME}.js\"\r\n"
      body << "Content-Type: application/javascript+module\r\n\r\n"
      body << script_content
      body << "\r\n"

      body << "--#{boundary}--\r\n"
      body
    end

    def list_routes
      uri = URI("https://api.cloudflare.com/client/v4/zones/#{ZONE_ID}/workers/routes")

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{API_TOKEN}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      JSON.parse(response.body)
    end

    def create_route
      uri = URI("https://api.cloudflare.com/client/v4/zones/#{ZONE_ID}/workers/routes")

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{API_TOKEN}"
      request['Content-Type'] = 'application/json'
      request.body = {
        pattern: ROUTE_PATTERN,
        script: SCRIPT_NAME
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      JSON.parse(response.body)
    end
  end
end
```

---

## API Reference Summary

### Worker Scripts

| Operation            | Method | Endpoint                                               |
| -------------------- | ------ | ------------------------------------------------------ |
| Upload/Update Worker | PUT    | `/accounts/{account_id}/workers/scripts/{script_name}` |
| Delete Worker        | DELETE | `/accounts/{account_id}/workers/scripts/{script_name}` |
| List Workers         | GET    | `/accounts/{account_id}/workers/scripts`               |

**Docs:** https://developers.cloudflare.com/api/resources/workers/subresources/scripts/

### Worker Routes

| Operation    | Method | Endpoint                                     |
| ------------ | ------ | -------------------------------------------- |
| Create Route | POST   | `/zones/{zone_id}/workers/routes`            |
| List Routes  | GET    | `/zones/{zone_id}/workers/routes`            |
| Update Route | PUT    | `/zones/{zone_id}/workers/routes/{route_id}` |
| Delete Route | DELETE | `/zones/{zone_id}/workers/routes/{route_id}` |

**Docs:** https://developers.cloudflare.com/api/resources/workers/subresources/routes/

### HTMLRewriter

The HTMLRewriter API allows streaming HTML transformation without buffering the entire response.

**Docs:** https://developers.cloudflare.com/workers/runtime-apis/html-rewriter/

---

## Environment Variables Required

```bash
# Cloudflare credentials
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_ZONE_ID=your_zone_id
CLOUDFLARE_API_TOKEN=your_api_token

# Widget configuration
JWT_SECRET=your_jwt_secret_for_widget_auth
WIDGET_URL=https://chat.yourplatform.com/widget.js
```

---

## Testing

### 1. Deploy Worker Manually (curl)

```bash
# Set environment variables
export CF_ACCOUNT_ID="your_account_id"
export CF_ZONE_ID="your_zone_id"
export CF_API_TOKEN="your_api_token"

# Create worker script file
cat > /tmp/widget-injector.js << 'EOF'
export default {
  async fetch(request, env, ctx) {
    const response = await fetch(request);
    const contentType = response.headers.get('content-type') || '';

    if (!contentType.includes('text/html')) {
      return response;
    }

    return new HTMLRewriter()
      .on('body', {
        element(el) {
          el.append(`
            <script>
              (function(){
                var d = document.createElement('div');
                d.style.cssText = 'position:fixed;bottom:20px;right:20px;background:#10b981;color:white;padding:12px 20px;border-radius:24px;z-index:99999;font-family:system-ui;';
                d.textContent = '✓ It Works!';
                document.body.appendChild(d);
              })();
            </script>
          `, { html: true });
        }
      })
      .transform(response);
  }
};
EOF

# Deploy worker
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/scripts/widget-injector" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -F 'metadata={"main_module": "widget-injector.js", "compatibility_date": "2024-01-01"};type=application/json' \
  -F 'widget-injector.js=@/tmp/widget-injector.js;type=application/javascript+module'

# Create route
curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/workers/routes" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"pattern": "*.previews.yourplatform.com/*", "script": "widget-injector"}'
```

### 2. Verify Injection

1. Deploy a sandbox app
2. Navigate to `https://myapp.previews.yourplatform.com`
3. Check for green "It Works!" bubble in bottom-right corner
4. Inspect HTML source to see injected script

---

## Future Enhancements

1. **Full Chat Widget**: Replace simple bubble with full chat interface
2. **WebSocket Connection**: Connect widget to Rails backend via Action Cable
3. **JWT Token Security**: Validate tokens in Rails controller
4. **Page Context**: Send current URL, title, DOM info to AI agent
5. **Navigation Commands**: Allow AI to navigate/click/fill via widget

---

## Troubleshooting

### Worker not triggering

1. Verify route pattern matches your subdomain
2. Check DNS record exists and is proxied (orange cloud)
3. Verify Worker is deployed: `GET /accounts/{account_id}/workers/scripts`

### Script not injected

1. Verify response Content-Type is `text/html`
2. Check Worker logs in Cloudflare dashboard
3. Ensure HTMLRewriter selector matches (`body` tag exists)

### Token verification fails

1. Ensure JWT_SECRET matches between Worker and Rails
2. Check token expiration (1 hour default)
3. Verify token is being passed in dataset attribute

---

## References

- Cloudflare Workers Documentation: https://developers.cloudflare.com/workers/
- HTMLRewriter API: https://developers.cloudflare.com/workers/runtime-apis/html-rewriter/
- Workers Routes: https://developers.cloudflare.com/workers/configuration/routing/routes/
- Workers REST API: https://developers.cloudflare.com/api/resources/workers/
- Multipart Upload Metadata: https://developers.cloudflare.com/workers/configuration/multipart-upload-metadata/
