# frozen_string_literal: true

module Rbrun
  class SandboxChannel < ApplicationCable::Channel
    def subscribed
      @sandbox = if ENV["RBRUN_DEV"]
        Sandbox.find_by(slug: params[:sandbox_id])
      else
        Sandbox.find_by(access_token: params[:token])
      end
      @sandbox ? stream_for(@sandbox) : reject
    end

    def run_claude(data)
      return unless @sandbox
      return unless ENV["RBRUN_DEV"] || @sandbox.running?
      RunClaudeJob.perform_later(@sandbox.id, data["prompt"], session_id: data["session_id"])
    end

    def create_session(data)
      return unless @sandbox
      session = @sandbox.claude_sessions.create!(title: data["title"])
      SandboxChannel.broadcast_to(@sandbox, { type: "session_created", session: session.as_json })
    end
  end
end
