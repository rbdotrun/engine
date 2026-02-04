# frozen_string_literal: true

module Rbrun
  module Kubernetes
    # Installs K3s, Docker, and supporting infrastructure on a VM.
    # All commands go through release.run_ssh! -> CommandExecution -> CommandLog.
    class K3sInstaller
      REGISTRY_PORT = 30500
      REGISTRY_NAME = "app-registry"
      CLUSTER_CIDR = "10.42.0.0/16"
      SERVICE_CIDR = "10.43.0.0/16"
      CLOUD_INIT_TIMEOUT = 120
      REGISTRY_TIMEOUT = 60

      attr_reader :release

      def initialize(release)
        @release = release
      end

      def install!
        wait_for_cloud_init!
        network = discover_network_info
        install_docker!
        configure_docker!(network[:private_ip])
        configure_k3s_registries!
        install_k3s!(network[:public_ip], network[:private_ip], network[:interface])
        setup_kubeconfig!(network[:private_ip])
        deploy_priority_classes!
        deploy_registry!
        wait_for_registry!
        deploy_ingress_controller!
      end

      def uninstall!
        run_ssh!("sudo /usr/local/bin/k3s-uninstall.sh", raise_on_error: false)
        run_ssh!("sudo apt-get remove -y docker.io docker-compose", raise_on_error: false)
        run_ssh!("sudo rm -rf /etc/rancher /var/lib/rancher /etc/docker", raise_on_error: false)
      end

      private

        def wait_for_cloud_init!
          log_step("wait_cloud_init")
          CLOUD_INIT_TIMEOUT.times do |i|
            exec = run_ssh!("test -f /var/lib/cloud/instance/boot-finished && echo ready", raise_on_error: false)
            return if exec.output.include?("ready")
            sleep 5
          end
          raise K3sInstallError, "Cloud-init did not complete within #{CLOUD_INIT_TIMEOUT * 5} seconds"
        end

        def discover_network_info
          log_step("discover_network")

          # Get public IP
          exec = run_ssh!("curl -s ifconfig.me || curl -s icanhazip.com")
          public_ip = exec.output.strip

          # Get private IP and interface (RFC1918 ranges)
          exec = run_ssh!("ip -4 addr show | grep -oP '(?<=inet\\s)10\\.\\d+\\.\\d+\\.\\d+|172\\.(1[6-9]|2[0-9]|3[01])\\.\\d+\\.\\d+|192\\.168\\.\\d+\\.\\d+'")
          private_ip = exec.output.strip.split("\n").first

          unless private_ip
            raise K3sInstallError, "Could not detect private IP. Ensure server has a private network attached."
          end

          # Get interface for private IP
          exec = run_ssh!("ip -4 addr show | grep '#{private_ip}' -B2 | grep -oP '(?<=: )[^:@]+(?=:)'")
          interface = exec.output.strip.split("\n").last || "eth0"

          { public_ip:, private_ip:, interface: }
        end

        def install_docker!
          # Idempotent: skip if docker already installed and running
          check = run_ssh!("docker --version && systemctl is-active docker", raise_on_error: false)
          if check.success?
            puts "      [k3s:install_docker] already installed, skipping"
            return
          end

          log_step("install_docker")
          run_ssh!(<<~BASH)
            export DEBIAN_FRONTEND=noninteractive
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker.io docker-compose
            sudo systemctl enable docker
            sudo systemctl start docker
            sudo usermod -aG docker #{Naming.default_user}
          BASH
        end

        def configure_docker!(private_ip)
          log_step("configure_docker")
          daemon_json = {
            "insecure-registries" => [
              "#{private_ip}:5001",
              "localhost:#{REGISTRY_PORT}"
            ]
          }.to_json

          run_ssh!("sudo mkdir -p /etc/docker")
          run_ssh!("sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'\n#{daemon_json}\nEOF")
          run_ssh!("sudo systemctl restart docker")
        end

        def configure_k3s_registries!
          log_step("configure_k3s_registries")
          registries_yaml = <<~YAML
            mirrors:
              "localhost:#{REGISTRY_PORT}":
                endpoint:
                  - "http://registry.default.svc.cluster.local:5000"
                  - "http://localhost:#{REGISTRY_PORT}"
          YAML

          run_ssh!("sudo mkdir -p /etc/rancher/k3s")
          run_ssh!("sudo tee /etc/rancher/k3s/registries.yaml > /dev/null << 'EOF'\n#{registries_yaml}\nEOF")
        end

        def install_k3s!(public_ip, private_ip, interface)
          # Idempotent: skip if k3s already installed and running
          check = run_ssh!("kubectl get nodes 2>/dev/null | grep -q Ready", raise_on_error: false)
          if check.success?
            puts "      [k3s:install_k3s] already installed, skipping"
            return
          end

          log_step("install_k3s")

          k3s_args = [
            "--disable traefik",
            "--disable servicelb",
            "--flannel-backend=wireguard-native",
            "--flannel-iface=#{interface}",
            "--bind-address=#{private_ip}",
            "--advertise-address=#{private_ip}",
            "--node-ip=#{private_ip}",
            "--node-external-ip=#{public_ip}",
            "--write-kubeconfig-mode=644",
            "--cluster-cidr=#{CLUSTER_CIDR}",
            "--service-cidr=#{SERVICE_CIDR}"
          ].join(" ")

          run_ssh!(<<~BASH, timeout: 300)
            curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="#{k3s_args}" sh -
          BASH

          # Wait for K3s to be ready
          30.times do
            exec = run_ssh!("sudo kubectl get nodes", raise_on_error: false)
            break if exec.success? && exec.output.include?("Ready")
            sleep 5
          end
        end

        def setup_kubeconfig!(private_ip)
          log_step("setup_kubeconfig")
          user = Naming.default_user

          run_ssh!(<<~BASH)
            mkdir -p /home/#{user}/.kube
            sudo cp /etc/rancher/k3s/k3s.yaml /home/#{user}/.kube/config
            sudo sed -i 's/127.0.0.1/#{private_ip}/g' /home/#{user}/.kube/config
            sudo chown -R #{user}:#{user} /home/#{user}/.kube
            chmod 600 /home/#{user}/.kube/config
          BASH
        end

        def deploy_priority_classes!
          log_step("deploy_priority_classes")
          apply_manifest!(Resources.priority_class_yaml)
        end

        def deploy_registry!
          log_step("deploy_registry")
          apply_manifest!(registry_manifest)
        end

        def registry_manifest
          <<~YAML
            apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: registry-pvc
              namespace: default
            spec:
              accessModes: [ReadWriteOnce]
              resources:
                requests:
                  storage: 10Gi
            ---
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: registry
              namespace: default
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: registry
              template:
                metadata:
                  labels:
                    app: registry
                spec:
                  containers:
                  - name: registry
                    image: registry:2
                    ports:
                    - containerPort: 5000
                    volumeMounts:
                    - name: registry-data
                      mountPath: /var/lib/registry
                  volumes:
                  - name: registry-data
                    persistentVolumeClaim:
                      claimName: registry-pvc
            ---
            apiVersion: v1
            kind: Service
            metadata:
              name: registry
              namespace: default
            spec:
              type: NodePort
              selector:
                app: registry
              ports:
              - port: 5000
                targetPort: 5000
                nodePort: #{REGISTRY_PORT}
          YAML
        end

        def wait_for_registry!
          log_step("wait_registry")
          REGISTRY_TIMEOUT.times do
            exec = run_ssh!("curl -sf http://localhost:#{REGISTRY_PORT}/v2/ && echo ok", raise_on_error: false)
            return if exec.output.include?("ok")
            sleep 2
          end
          raise K3sInstallError, "Registry did not become ready within #{REGISTRY_TIMEOUT * 2} seconds"
        end

        def deploy_ingress_controller!
          log_step("deploy_ingress")
          apply_manifest!(ingress_controller_manifest)

          # Wait for ingress controller to be ready
          kubeconfig = "/home/#{Naming.default_user}/.kube/config"
          30.times do
            exec = run_ssh!("kubectl --kubeconfig=#{kubeconfig} -n ingress-nginx get pods -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}'", raise_on_error: false)
            break if exec.output.include?("Running")
            sleep 5
          end

          # Patch to use predictable NodePorts (30080 for HTTP, 30443 for HTTPS)
          patch_json = '[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080},{"op":"replace","path":"/spec/ports/1/nodePort","value":30443}]'
          run_ssh!("kubectl --kubeconfig=#{kubeconfig} patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='#{patch_json}'", raise_on_error: false)
        end

        def ingress_controller_manifest
          "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml"
        end

        def apply_manifest!(yaml)
          kubeconfig = "/home/#{Naming.default_user}/.kube/config"
          if yaml.start_with?("http")
            run_ssh!("kubectl --kubeconfig=#{kubeconfig} apply -f #{yaml}")
          else
            run_ssh!("kubectl --kubeconfig=#{kubeconfig} apply -f - << 'EOF'\n#{yaml}\nEOF")
          end
        end

        def run_ssh!(command, raise_on_error: true, timeout: 300)
          release.run_ssh!(command, raise_on_error:, timeout:)
        end

        def log_step(category)
          release.command_executions.create!(kind: "exec", command: category, category:)
          puts "      [k3s:#{category}]"
        end
    end

    class K3sInstallError < StandardError; end
  end
end
