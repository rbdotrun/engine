# frozen_string_literal: true

module Rbrun
  # == Schema Information
  #
  # Table name: rbrun_sandbox_envs
  #
  #  id         :integer          not null, primary key
  #  sandbox_id :integer          not null
  #  key        :string           not null
  #  value      :text
  #  secret     :boolean          default(false)
  #  created_at :datetime
  #  updated_at :datetime
  #
  class SandboxEnv < ApplicationRecord
    belongs_to :sandbox

    validates :key, presence: true,
                    uniqueness: { scope: :sandbox_id },
                    format: { with: /\A[A-Z_][A-Z0-9_]*\z/, message: "must be uppercase with underscores" }
  end
end
