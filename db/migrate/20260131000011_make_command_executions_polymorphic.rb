# frozen_string_literal: true

class MakeCommandExecutionsPolymorphic < ActiveRecord::Migration[8.0]
  def up
    # Add polymorphic columns
    add_column :rbrun_command_executions, :executable_type, :string
    add_column :rbrun_command_executions, :executable_id, :bigint

    # Migrate existing data: sandbox_id -> executable
    execute <<~SQL
      UPDATE rbrun_command_executions
      SET executable_type = 'Rbrun::Sandbox',
          executable_id = sandbox_id
      WHERE sandbox_id IS NOT NULL
    SQL

    # Add index for polymorphic lookup
    add_index :rbrun_command_executions, [:executable_type, :executable_id], name: "index_command_executions_on_executable"

    # Make sandbox_id nullable
    change_column_null :rbrun_command_executions, :sandbox_id, true

    # Remove foreign key constraint (if exists)
    remove_foreign_key :rbrun_command_executions, :rbrun_sandboxes if foreign_key_exists?(:rbrun_command_executions, :rbrun_sandboxes)
  end

  def down
    # Remove polymorphic columns
    remove_index :rbrun_command_executions, name: "index_command_executions_on_executable"
    remove_column :rbrun_command_executions, :executable_type
    remove_column :rbrun_command_executions, :executable_id

    # Make sandbox_id required again
    change_column_null :rbrun_command_executions, :sandbox_id, false

    # Re-add foreign key
    add_foreign_key :rbrun_command_executions, :rbrun_sandboxes
  end
end
