# frozen_string_literal: true

require "test_helper"

module Rbrun
  class ProvisionSandboxJobTest < ActiveSupport::TestCase
    test "uses default queue" do
      assert_equal "default", ProvisionSandboxJob.new.queue_name
    end
  end
end
