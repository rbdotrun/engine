# frozen_string_literal: true

module Rbrun
  class Release
    # Minimal Kubernetes operations for releases.
    # All commands go through kubectl_client → ssh → CommandExecution.
    module KubernetesOps
      extend ActiveSupport::Concern

      # Get logs from deployment
      def logs(process: :web, tail: 100, &block)
        kubectl_client.logs("#{k8s_prefix}-#{process}", tail:, &block)
      end

      # Execute command in pod
      def exec(command:, process: :web)
        deployment = "#{k8s_prefix}-#{process}"
        pod = kubectl_client.get_pod_for_deployment(deployment)
        raise "Pod not found for deployment: #{deployment}" unless pod
        kubectl_client.exec(pod, command)
      end

      # Scale deployment
      def scale(process: :web, replicas:)
        kubectl_client.scale("#{k8s_prefix}-#{process}", replicas:)
      end

      # Restart deployment
      def rollout_restart(process: :web)
        kubectl_client.rollout_restart("#{k8s_prefix}-#{process}")
      end

      # Check rollout status
      def rollout_status(process: :web)
        kubectl_client.rollout_status("#{k8s_prefix}-#{process}")
      end

      private

        def kubectl_client
          @kubectl_client ||= Rbrun::Kubernetes::Kubectl.new(self)
        end

        def k8s_prefix
          Naming.release_prefix
        end
    end
  end
end
