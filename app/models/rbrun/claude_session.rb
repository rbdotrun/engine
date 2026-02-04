# frozen_string_literal: true

module Rbrun
  # == Schema Information
  #
  # Table name: rbrun_claude_sessions
  #
  #  id           :integer          not null, primary key
  #  sandbox_id   :integer          not null
  #  session_uuid :string           not null
  #  title        :string
  #  git_diff     :text
  #  created_at   :datetime
  #  updated_at   :datetime
  #
  class ClaudeSession < ApplicationRecord
    include ClaudeSession::Runnable

    belongs_to :sandbox
    has_many :command_executions, dependent: :nullify

    before_validation :generate_session_uuid, on: :create

    validates :session_uuid, presence: true, uniqueness: true

    def display_name
      title.presence || "Session #{id}"
    end

    def cli_flag
      resumable? ? "--resume" : "--session-id"
    end

    def resumable?
      # TODO: harden by also checking if Claude session file exists on disk:
      # ~/.claude/projects/{project_path}/#{session_uuid}.jsonl
      command_executions.where(exit_code: 0).exists?
    end

    def as_json(options = {})
      super(options.merge(methods: [:display_name]))
    end

    private

      def generate_session_uuid
        self.session_uuid ||= SecureRandom.uuid
      end
  end
end
