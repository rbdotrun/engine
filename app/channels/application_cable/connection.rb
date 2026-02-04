# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :sandbox_token

    def connect
      self.sandbox_token = request.params[:token]
      return if ENV["RBRUN_DEV"]
      reject_unauthorized_connection unless Rbrun::Sandbox.exists?(access_token: sandbox_token)
    end
  end
end
