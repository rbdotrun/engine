# frozen_string_literal: true

class CreateRbrunSandboxEnvs < ActiveRecord::Migration[8.0]
  def change
    create_table :rbrun_sandbox_envs do |t|
      t.references :sandbox, null: false, foreign_key: { to_table: :rbrun_sandboxes }
      t.string :key, null: false
      t.text :value
      t.boolean :secret, default: false, null: false
      t.timestamps
    end

    add_index :rbrun_sandbox_envs, [:sandbox_id, :key], unique: true
  end
end
