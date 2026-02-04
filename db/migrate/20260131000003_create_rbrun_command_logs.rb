# frozen_string_literal: true

class CreateRbrunCommandLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :rbrun_command_logs do |t|
      t.references :command_execution, null: false,
                   foreign_key: { to_table: :rbrun_command_executions }
      t.string :stream, null: false
      t.integer :line_number, null: false
      t.text :content, null: false
      t.timestamps
    end

    add_index :rbrun_command_logs,
              [:command_execution_id, :stream, :line_number],
              unique: true,
              name: "idx_rbrun_logs_unique_line"
  end
end
