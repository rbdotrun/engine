# frozen_string_literal: true

class CreateRbrunSandboxes < ActiveRecord::Migration[8.0]
  def change
    create_table :rbrun_sandboxes do |t|
      t.string :state, default: "pending", null: false
      t.string :slug, index: { unique: true }
      t.text :last_error
      t.text :ssh_public_key
      t.text :ssh_private_key
      t.text :docker_compose
      t.text :env
      t.text :setup
      t.boolean :exposed, default: false, null: false
      t.timestamps
    end
  end
end
