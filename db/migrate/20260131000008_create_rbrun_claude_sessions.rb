# frozen_string_literal: true

class CreateRbrunClaudeSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :rbrun_claude_sessions do |t|
      t.references :sandbox, null: false, foreign_key: { to_table: :rbrun_sandboxes }
      t.string :session_uuid, null: false
      t.string :title

      t.timestamps
    end

    add_index :rbrun_claude_sessions, :session_uuid, unique: true
  end
end
