# frozen_string_literal: true

class RemoveDetectedConfigFromSandboxes < ActiveRecord::Migration[8.0]
  def change
    remove_column :rbrun_sandboxes, :detected_config, :json
  end
end
