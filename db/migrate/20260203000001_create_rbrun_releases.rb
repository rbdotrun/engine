# frozen_string_literal: true

class CreateRbrunReleases < ActiveRecord::Migration[7.1]
  def change
    create_table :rbrun_releases do |t|
      t.string :state, default: "pending", null: false
      t.string :ref
      t.string :server_id
      t.string :server_ip
      t.text :ssh_public_key
      t.text :ssh_private_key
      t.string :tunnel_id
      t.string :registry_tag
      t.text :last_error
      t.datetime :deployed_at

      t.timestamps
    end

    add_index :rbrun_releases, :state
  end
end
