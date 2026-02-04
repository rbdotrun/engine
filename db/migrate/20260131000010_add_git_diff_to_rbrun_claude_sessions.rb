# frozen_string_literal: true

class AddGitDiffToRbrunClaudeSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :rbrun_claude_sessions, :git_diff, :text
  end
end
