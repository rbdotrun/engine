# frozen_string_literal: true

module Rbrun
  class LogsController < ApplicationController
    def index
      @sandbox = Sandbox.find(params[:sandbox_id])

      logs = @sandbox.command_logs.order(id: :desc)
      logs = logs.where("rbrun_command_logs.id < ?", params[:before_id]) if params[:before_id].present?
      @logs = logs.limit(params.fetch(:limit, 20).to_i).to_a.reverse

      render partial: "rbrun/logs/log_lines", locals: { logs: @logs }
    end
  end
end
