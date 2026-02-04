# frozen_string_literal: true

class AddAccessTokenToRbrunSandboxes < ActiveRecord::Migration[8.0]
  def change
    add_column :rbrun_sandboxes, :access_token, :string
    add_index :rbrun_sandboxes, :access_token, unique: true
  end
end
