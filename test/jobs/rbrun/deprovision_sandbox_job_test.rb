# frozen_string_literal: true

require "test_helper"

module Rbrun
  class DeprovisionSandboxJobTest < ActiveSupport::TestCase
    test "uses default queue" do
      assert_equal "default", DeprovisionSandboxJob.new.queue_name
    end
  end
end
