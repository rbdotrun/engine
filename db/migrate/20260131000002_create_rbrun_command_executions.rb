# frozen_string_literal: true

class CreateRbrunCommandExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :rbrun_command_executions do |t|
      t.references :sandbox, null: false, foreign_key: { to_table: :rbrun_sandboxes }
      t.text :command, null: false
      t.string :kind, default: "exec", null: false
      t.string :tag
      t.string :category
      t.integer :exit_code
      t.datetime :started_at
      t.datetime :finished_at
      t.string :image
      t.string :container_id
      t.integer :port
      t.boolean :public, default: false
      t.timestamps
    end

    add_index :rbrun_command_executions, :kind
    add_index :rbrun_command_executions, :tag
  end
end
