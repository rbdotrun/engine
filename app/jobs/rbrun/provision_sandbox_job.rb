# frozen_string_literal: true

module Rbrun
  class ProvisionSandboxJob < ApplicationJob
    queue_as :default

    def perform(sandbox)
      sandbox.provision_now!
    end
  end
end
