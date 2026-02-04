# frozen_string_literal: true

module Rbrun
  class SandboxesController < ApplicationController
    before_action :set_sandbox, only: %i[show destroy toggle_expose]

    def index
      @sandboxes = Sandbox.order(created_at: :desc)
      @config = Rbrun.configuration
    end

    # One-click creation - no form needed
    def create
      @sandbox = Sandbox.create!
      @sandbox.provision_later!
      redirect_to sandbox_path(@sandbox)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to sandboxes_path, alert: e.message
    end

    def show
      @logs = @sandbox.command_logs.order(id: :desc).limit(20).to_a.reverse
    end

    def destroy
      @sandbox.deprovision_later!
      redirect_to sandbox_path(@sandbox), notice: "Stopping sandbox..."
    end

    def toggle_expose
      config = Rbrun.configuration

      if @sandbox.exposed?
        @sandbox.delete_compose_tunnel!
        @sandbox.update!(exposed: false)
      else
        unless config.cloudflare_configured?
          return redirect_to sandbox_path(@sandbox), alert: "Cloudflare not configured"
        end
        @sandbox.update!(exposed: true)
        @sandbox.setup_compose_tunnel! if @sandbox.running?
      end
      redirect_to sandbox_path(@sandbox)
    end

    private

      def set_sandbox
        @sandbox = Sandbox.find(params[:id])
      end
  end
end
