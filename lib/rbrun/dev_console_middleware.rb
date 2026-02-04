# frozen_string_literal: true

module Rbrun
  class DevConsoleMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      content_type = headers["Content-Type"] || ""
      return [status, headers, response] unless content_type.include?("text/html")

      request = Rack::Request.new(env)
      sandbox_id = request.params["rbrun_sandbox"] || Sandbox.first&.id
      return [status, headers, response] unless sandbox_id

      config = {
        sandboxId: sandbox_id.to_s,
        wsUrl: "ws://localhost:3000/cable",
        apiUrl: "/rbrun",
        token: "DEV_BYPASS"
      }

      body = +""
      response.each { |part| body << part }
      response.close if response.respond_to?(:close)

      injection = <<~HTML
        <script>window.RBRUN_CONFIG = #{config.to_json};</script>
        <script src="#{console_js_path}"></script>
      HTML

      body.sub!("</body>", "#{injection}</body>")
      headers["Content-Length"] = body.bytesize.to_s

      [status, headers, [body]]
    end

    private

      def console_js_path
        manifest_path = Engine.root.join("app/javascript/rbrun/.vite/manifest.json")
        if File.exist?(manifest_path)
          manifest = JSON.parse(File.read(manifest_path))
          filename = manifest.dig("src/index.tsx", "file")
          return "/rbrun/#{filename}" if filename
        end
        "/rbrun/console.js"
      end
  end
end
