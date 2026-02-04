# frozen_string_literal: true

class AddEnvironmentAndBranchToReleases < ActiveRecord::Migration[8.0]
  def change
    add_column :rbrun_releases, :environment, :string, default: "production", null: false
    add_column :rbrun_releases, :branch, :string, default: "main", null: false
    add_index :rbrun_releases, :environment
  end
end
