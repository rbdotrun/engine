# frozen_string_literal: true

require "test_helper"

module Rbrun
  class LogsControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    def setup
      super
      @routes = Engine.routes
      @sandbox = Sandbox.create!
      @execution = @sandbox.command_executions.create!(command: "echo test", kind: "exec")
    end

    test "GET /sandboxes/:sandbox_id/logs returns log lines" do
      @execution.command_logs.create!(stream: "output", line_number: 1, content: "line 1")
      @execution.command_logs.create!(stream: "output", line_number: 2, content: "line 2")

      get sandbox_logs_url(@sandbox)
      assert_response :success
      assert_includes response.body, "line 1"
      assert_includes response.body, "line 2"
    end

    test "GET /sandboxes/:sandbox_id/logs respects before_id parameter" do
      log1 = @execution.command_logs.create!(stream: "output", line_number: 1, content: "older")
      log2 = @execution.command_logs.create!(stream: "output", line_number: 2, content: "newer")

      get sandbox_logs_url(@sandbox, before_id: log2.id)
      assert_response :success
      assert_includes response.body, "older"
      refute_includes response.body, "newer"
    end

    test "GET /sandboxes/:sandbox_id/logs respects limit parameter" do
      30.times do |i|
        @execution.command_logs.create!(stream: "output", line_number: i + 1, content: "line #{i + 1}")
      end

      get sandbox_logs_url(@sandbox, limit: 5)
      assert_response :success

      # Should only have 5 log entries (data-log-id appears once per log)
      assert_equal 5, response.body.scan(/data-log-id/).count
    end

    test "GET /sandboxes/:sandbox_id/logs returns empty when no logs" do
      get sandbox_logs_url(@sandbox)
      assert_response :success
    end

    test "GET /sandboxes/:sandbox_id/logs includes data-log-id attributes" do
      log = @execution.command_logs.create!(stream: "output", line_number: 1, content: "test")

      get sandbox_logs_url(@sandbox)
      assert_response :success
      assert_includes response.body, "data-log-id=\"#{log.id}\""
    end

    private

      def default_url_options
        { host: "localhost" }
      end
  end
end
