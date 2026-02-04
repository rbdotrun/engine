# frozen_string_literal: true

module Rbrun
  class DeprovisionSandboxJob < ApplicationJob
    queue_as :default

    def perform(sandbox)
      sandbox.deprovision_now!
    end
  end
end
