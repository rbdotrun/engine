# frozen_string_literal: true

module Rbrun
  class Sandbox
    # Handles real-time broadcasting of provisioning progress via Turbo Streams.
    #
    # Broadcasts status changes, progress messages, and command output to
    # subscribed clients viewing the sandbox show page.
    #
    module Broadcastable
      extend ActiveSupport::Concern

      LogStub = Struct.new(:id, :content)

      included do
        include ActionView::RecordIdentifier
        include Turbo::Broadcastable
      end

      # Broadcast a provisioning step (category label, no command_logs).
      def broadcast_step(execution)
        log = LogStub.new(nil, execution.category_label)
        broadcast_append_to self,
          target: dom_id(self, :output_logs),
          partial: "rbrun/logs/log_line",
          locals: { log: }
      end

      # Broadcast a log line to the output container.
      def broadcast_output(execution, line)
        log = execution.command_logs.order(:id).last
        broadcast_append_to self,
          target: dom_id(self, :output_logs),
          partial: "rbrun/logs/log_line",
          locals: { log: }
      end
    end
  end
end
