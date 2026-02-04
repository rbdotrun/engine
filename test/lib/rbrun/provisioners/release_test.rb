# frozen_string_literal: true

require "test_helper"

module Rbrun
  module Provisioners
    class ReleaseTest < ActiveSupport::TestCase
      def setup
        super
        Rbrun.reset_configuration!
        Rbrun.configuration.compute(:hetzner) { |c| c.api_key = "test_key" }
        Rbrun.configuration.git do |g|
          g.pat = "github_token"
          g.repo = "owner/repo"
        end
        @release = Rbrun::Release.create!
        @provisioner = Release.new(@release)
      end

      test "provisioner initializes with release" do
        assert_equal @release, @provisioner.release
      end

      # ─────────────────────────────────────────────────────────────
      # Database Password Tests
      # ─────────────────────────────────────────────────────────────

      test "configured_db_password returns nil when not set" do
        Rbrun.configuration.database(:postgres)

        assert_nil @provisioner.send(:configured_db_password)
      end

      test "configured_db_password returns password when set" do
        Rbrun.configuration.database(:postgres) { |db| db.password = "my_secret_pw" }

        assert_equal "my_secret_pw", @provisioner.send(:configured_db_password)
      end

      test "configured_db_password returns nil when no postgres configured" do
        assert_nil @provisioner.send(:configured_db_password)
      end

      # ─────────────────────────────────────────────────────────────
      # SSH Key Tests (releases use static config keys)
      # ─────────────────────────────────────────────────────────────

      test "ssh_client uses config ssh_private_key" do
        Dir.mktmpdir do |dir|
          private_key_path = File.join(dir, "test_key")
          public_key_path = "#{private_key_path}.pub"

          File.write(private_key_path, "CONFIG_PRIVATE_KEY")
          File.write(public_key_path, "ssh-rsa CONFIG_PUBLIC test@example.com")

          Rbrun.configuration.compute_config.ssh_key_path = private_key_path
          @release.update!(server_ip: "1.2.3.4")

          client = @release.ssh_client
          assert_equal "CONFIG_PRIVATE_KEY", client.instance_variable_get(:@private_key)
        end
      end

      test "config ssh_public_key reads from file" do
        Dir.mktmpdir do |dir|
          private_key_path = File.join(dir, "test_key")
          public_key_path = "#{private_key_path}.pub"

          File.write(private_key_path, "PRIVATE")
          File.write(public_key_path, "ssh-rsa PUBLIC test@example.com")

          Rbrun.configuration.compute_config.ssh_key_path = private_key_path

          assert_equal "ssh-rsa PUBLIC test@example.com", Rbrun.configuration.compute_config.ssh_public_key
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Provision/Redeploy Tests
      # ─────────────────────────────────────────────────────────────

      test "provision! runs all steps even if already deployed (idempotent)" do
        @release.update!(state: "deployed")

        # Configure app so build_and_push_image! is called
        Rbrun.configuration.app do |a|
          a.process(:web) { |p| p.port = 3000 }
        end

        steps_called = []

        @provisioner.stub(:create_infrastructure!, -> { steps_called << :infra }) do
          @provisioner.stub(:install_k3s!, -> { steps_called << :k3s }) do
            @provisioner.stub(:build_and_push_image!, -> { steps_called << :build }) do
              @provisioner.stub(:deploy_kubernetes!, -> { steps_called << :deploy }) do
                @provisioner.stub(:wait_for_rollout!, -> { steps_called << :rollout }) do
                  @provisioner.provision!
                end
              end
            end
          end
        end

        assert_includes steps_called, :infra, "create_infrastructure! should be called"
        assert_includes steps_called, :k3s, "install_k3s! should be called"
        assert_includes steps_called, :build, "build_and_push_image! should be called"
        assert_includes steps_called, :deploy, "deploy_kubernetes! should be called"
        assert_includes steps_called, :rollout, "wait_for_rollout! should be called"
      end

      test "model provision! calls provisioner even when deployed" do
        @release.update!(state: "deployed")

        provisioner_called = false
        @release.stub(:provisioner, -> {
          mock = Minitest::Mock.new
          mock.expect(:provision!, nil) { provisioner_called = true }
          mock
        }.call) do
          @release.provision!
        end

        assert provisioner_called, "provisioner.provision! should be called even when deployed"
      end

      test "redeploy! raises if not deployed" do
        @release.update!(state: "pending")

        assert_raises(RuntimeError, "Release not deployed") do
          @provisioner.redeploy!
        end
      end

      test "redeploy! calls deploy_kubernetes!" do
        @release.update!(state: "deployed")

        deploy_called = false
        @provisioner.stub(:build_and_push_image!, -> {}) do
          @provisioner.stub(:deploy_kubernetes!, -> { deploy_called = true }) do
            @provisioner.stub(:wait_for_rollout!, -> {}) do
              @provisioner.redeploy!
            end
          end
        end

        assert deploy_called, "deploy_kubernetes! should be called on redeploy"
      end
    end
  end
end
