# frozen_string_literal: true

module Rbrun
  module Cloudflare
    # Worker script generation and deployment helpers for Cloudflare Workers.
    module Worker
      class << self
        def script
          cookie_name = Naming.auth_cookie
          <<~JS
            import consoleScript from './console.js';

            function parseCookies(cookieHeader) {
              const cookies = {};
              if (!cookieHeader) return cookies;
              cookieHeader.split(';').forEach(cookie => {
                const [name, ...rest] = cookie.trim().split('=');
                if (name) cookies[name] = rest.join('=');
              });
              return cookies;
            }

            export default {
              async fetch(request, env) {
                const url = new URL(request.url);
                const cookies = parseCookies(request.headers.get('Cookie') || '');
                const tokenParam = url.searchParams.get('token');
                const cookieToken = cookies['#{cookie_name}'];

                const token = tokenParam || cookieToken;
                if (!token || token !== env.ACCESS_TOKEN) {
                  return new Response('Not Found', { status: 404 });
                }

                // Set cookie on first access, redirect to clean URL
                if (tokenParam && !cookieToken) {
                  url.searchParams.delete('token');
                  return new Response(null, {
                    status: 302,
                    headers: {
                      'Location': url.toString(),
                      'Set-Cookie': `#{cookie_name}=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=86400`
                    }
                  });
                }

                const response = await fetch(request);
                const ct = response.headers.get('content-type') || '';
                if (!ct.includes('text/html')) return response;

                return new HTMLRewriter()
                  .on('body', {
                    element(el) {
                      el.append(`<script>
                        window.RBRUN_CONFIG = {
                          sandboxId: '${env.SANDBOX_SLUG}',
                          wsUrl: '${env.WS_URL}',
                          apiUrl: '${env.API_URL}',
                          token: '${token}'
                        };
                      </script>
                      <script>${consoleScript}</script>`, { html: true });
                    }
                  })
                  .transform(response);
              }
            };
          JS
        end

        def bindings(slug, access_token)
          ws_url = Rbrun.configuration.websocket_url || ENV["RBRUN_WEBSOCKET_URL"] || "wss://local.rb.run/cable"
          api_url = Rbrun.configuration.api_url || ENV["RBRUN_API_URL"] || "https://local.rb.run/rbrun"

          [
            { type: "plain_text", name: "ACCESS_TOKEN", text: access_token },
            { type: "plain_text", name: "SANDBOX_SLUG", text: slug.to_s },
            { type: "plain_text", name: "WS_URL", text: ws_url },
            { type: "plain_text", name: "API_URL", text: api_url }
          ]
        end

        def read_console_js
          path = Rbrun::Engine.root.join("app/javascript/rbrun/console.js")
          raise Rbrun::HttpErrors::Error, "console.js not found at #{path}. Run: cd console && npm run build" unless File.exist?(path)
          File.read(path)
        end

        def build_multipart(boundary, metadata, script_content)
          console_js_content = read_console_js
          console_module = "export default #{console_js_content.to_json};"

          parts = []
          parts << "--#{boundary}\r\n"
          parts << "Content-Disposition: form-data; name=\"metadata\"\r\n"
          parts << "Content-Type: application/json\r\n\r\n"
          parts << metadata.to_json
          parts << "\r\n--#{boundary}\r\n"
          parts << "Content-Disposition: form-data; name=\"worker.js\"; filename=\"worker.js\"\r\n"
          parts << "Content-Type: application/javascript+module\r\n\r\n"
          parts << script_content
          parts << "\r\n--#{boundary}\r\n"
          parts << "Content-Disposition: form-data; name=\"console.js\"; filename=\"console.js\"\r\n"
          parts << "Content-Type: application/javascript+module\r\n\r\n"
          parts << console_module
          parts << "\r\n--#{boundary}--\r\n"
          parts.join
        end
      end
    end
  end
end
