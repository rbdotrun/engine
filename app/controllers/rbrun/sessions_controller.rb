# frozen_string_literal: true

module Rbrun
  class SessionsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    before_action :set_cors_headers
    before_action :set_sandbox, except: [:options]
    before_action :set_session, only: [:show]

    def options
      head :ok
    end

    def index
      sessions = @sandbox.claude_sessions.order(created_at: :desc)
      render json: sessions
    end

    def create
      session = @sandbox.claude_sessions.create!(title: params[:title])
      render json: session, status: :created
    end

    def show
      render json: @session.as_json.merge(
        history: @session.command_executions.includes(:command_logs).map do |exec|
          {
            id: exec.id,
            exit_code: exec.exit_code,
            logs: exec.command_logs.order(:line_number).pluck(:content)
          }
        end
      )
    end

    private

      def set_cors_headers
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type"
      end

      def set_sandbox
        @sandbox = Sandbox.find_by!(slug: params[:sandbox_id])
      end

      def set_session
        @session = @sandbox.claude_sessions.find(params[:id])
      end
  end
end
