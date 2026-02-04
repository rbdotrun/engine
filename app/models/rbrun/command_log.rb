# frozen_string_literal: true

module Rbrun
  # == Schema Information
  #
  # Table name: rbrun_command_logs
  #
  #  id                   :integer          not null, primary key
  #  command_execution_id :integer          not null
  #  stream               :string           not null
  #  line_number          :integer          not null
  #  content              :text             not null
  #  created_at           :datetime
  #  updated_at           :datetime
  #
  class CommandLog < ApplicationRecord
    belongs_to :command_execution

    validates :stream, presence: true
    validates :line_number, presence: true, numericality: { greater_than: 0 }
    validates :content, presence: true

    scope :stdout, -> { where(stream: "stdout") }
    scope :stderr, -> { where(stream: "stderr") }
    scope :output, -> { where(stream: "output") }
    scope :ordered, -> { order(:line_number) }
  end
end
