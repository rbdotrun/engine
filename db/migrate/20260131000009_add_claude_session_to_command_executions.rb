# frozen_string_literal: true

class AddClaudeSessionToCommandExecutions < ActiveRecord::Migration[8.0]
  def change
    add_reference :rbrun_command_executions, :claude_session,
      null: true,
      foreign_key: { to_table: :rbrun_claude_sessions }
  end
end
