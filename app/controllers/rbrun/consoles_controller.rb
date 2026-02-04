# frozen_string_literal: true

module Rbrun
  class ConsolesController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def show
      filename = params[:filename] || "console.js"
      file_path = Engine.root.join("app/javascript/rbrun", filename)

      unless File.exist?(file_path) && filename.match?(/\Aconsole(\.[a-zA-Z0-9_-]+)?\.js\z/)
        return head :not_found
      end

      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
      response.headers["Access-Control-Allow-Headers"] = "Content-Type"
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"

      render file: file_path,
             content_type: "application/javascript",
             layout: false
    end
  end
end
