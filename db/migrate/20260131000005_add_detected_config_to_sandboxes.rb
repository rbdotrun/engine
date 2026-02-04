# frozen_string_literal: true

class AddDetectedConfigToSandboxes < ActiveRecord::Migration[8.0]
  def change
    add_column :rbrun_sandboxes, :detected_config, :json
  end
end
