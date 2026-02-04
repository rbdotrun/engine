# frozen_string_literal: true

module Rbrun
  class RunClaudeJob < ApplicationJob
    queue_as :default

    def perform(sandbox_id, prompt, session_id:)
      session = ClaudeSession.find(session_id)
      sandbox = session.sandbox

      execution = session.run_claude!(prompt) do |line|
        SandboxChannel.broadcast_to(sandbox, { type: "output", line:, session_id: session.id })
      end

      SandboxChannel.broadcast_to(sandbox, {
        type: "complete",
        success: execution.success?,
        session_id: session.id
      })
    rescue => e
      session = ClaudeSession.find_by(id: session_id)
      if session
        SandboxChannel.broadcast_to(session.sandbox, { type: "error", message: e.message, session_id: session.id })
      end
      raise
    end
  end
end
