# frozen_string_literal: true

module Rbrun
  module Kubernetes
    # Minimal kubectl wrapper via SSH.
    # All commands go through release.run_ssh! -> CommandExecution -> CommandLog.
    class Kubectl
      attr_reader :release

      def initialize(release)
        @release = release
      end

      # Apply manifest from YAML string
      def apply(manifest_yaml)
        run_ssh!("kubectl apply -f - << 'EOF'\n#{manifest_yaml}\nEOF")
      end

      # Delete resources from manifest
      def delete(manifest_yaml)
        run_ssh!("kubectl delete -f - --ignore-not-found << 'EOF'\n#{manifest_yaml}\nEOF", raise_on_error: false)
      end

      # Get resource as JSON
      def get(resource, name = nil, namespace: "default")
        cmd = "kubectl get #{resource}"
        cmd += " #{name}" if name
        cmd += " -n #{namespace} -o json"
        exec = run_ssh!(cmd, raise_on_error: false)
        return nil unless exec.success?
        JSON.parse(exec.output)
      end

      # Get logs from deployment
      def logs(deployment, tail: 100, namespace: "default")
        run_ssh!("kubectl logs deployment/#{deployment} -n #{namespace} --tail=#{tail}")
      end

      # Execute command in pod
      def exec(pod, command, namespace: "default")
        run_ssh!("kubectl exec #{pod} -n #{namespace} -- #{command}")
      end

      # Get pod name for deployment
      def get_pod_for_deployment(deployment, namespace: "default")
        exec = run_ssh!(
          "kubectl get pods -l app.kubernetes.io/name=#{deployment} -n #{namespace} -o jsonpath='{.items[0].metadata.name}'",
          raise_on_error: false
        )
        exec.success? ? exec.output.strip.tr("'", "") : nil
      end

      # Scale deployment
      def scale(deployment, replicas:, namespace: "default")
        run_ssh!("kubectl scale deployment/#{deployment} --replicas=#{replicas} -n #{namespace}")
      end

      # Restart deployment
      def rollout_restart(deployment, namespace: "default")
        run_ssh!("kubectl rollout restart deployment/#{deployment} -n #{namespace}")
      end

      # Wait for deployment rollout
      def rollout_status(deployment, namespace: "default", timeout: 300)
        run_ssh!("kubectl rollout status deployment/#{deployment} -n #{namespace} --timeout=#{timeout}s")
      end

      # Delete resource by name
      def delete_resource(resource, name, namespace: "default")
        run_ssh!("kubectl delete #{resource} #{name} -n #{namespace} --ignore-not-found", raise_on_error: false)
      end

      private

        def run_ssh!(command, raise_on_error: true, timeout: 300)
          release.run_ssh!(command, raise_on_error:, timeout:)
        end
    end
  end
end
