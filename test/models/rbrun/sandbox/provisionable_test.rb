# frozen_string_literal: true

require "test_helper"

module Rbrun
  class Sandbox
    class ProvisionableTest < ActiveSupport::TestCase
      def setup
        super
        Rbrun.configuration.compute(:hetzner) do |c|
          c.api_key = "test_key"
          c.server_type = "cx22"
          c.location = "fsn1"
          c.image = "ubuntu-22.04"
        end
        Rbrun.configuration.database(:postgres)
        Rbrun.configuration.app do |a|
          a.process(:web) { |p| p.port = 3000 }
        end
        @sandbox = Sandbox.create!
      end

      test "provisioner returns VM provisioner for hetzner" do
        assert_instance_of Provisioners::Sandbox, @sandbox.provisioner
      end

      test "provisioner returns VM provisioner for scaleway" do
        Rbrun.configuration.compute(:scaleway) do |c|
          c.api_key = "test_key"
          c.project_id = "test_project"
        end
        sandbox = Sandbox.create!

        assert_instance_of Provisioners::Sandbox, sandbox.provisioner
      end

      test "provisioner is memoized" do
        first_provisioner = @sandbox.provisioner
        second_provisioner = @sandbox.provisioner

        assert_same first_provisioner, second_provisioner
      end

      test "server_exists? delegates to provisioner" do
        @sandbox.provisioner.define_singleton_method(:server_exists?) { true }
        assert @sandbox.server_exists?

        @sandbox.provisioner.define_singleton_method(:server_exists?) { false }
        assert_not @sandbox.server_exists?
      end

      test "server_ip delegates to provisioner" do
        @sandbox.provisioner.define_singleton_method(:server_ip) { "1.2.3.4" }
        assert_equal "1.2.3.4", @sandbox.server_ip
      end

      test "preview_url delegates to provisioner" do
        @sandbox.provisioner.define_singleton_method(:preview_url) { "https://test.example.com" }
        assert_equal "https://test.example.com", @sandbox.preview_url
      end

      test "provision! does nothing when already running" do
        @sandbox.update!(state: "running")

        provision_called = false
        @sandbox.provisioner.define_singleton_method(:provision!) { provision_called = true }

        @sandbox.provision!

        assert_not provision_called
      end

      test "provision! delegates to provisioner when not running" do
        provision_called = false
        @sandbox.provisioner.define_singleton_method(:provision!) { provision_called = true }

        @sandbox.provision!

        assert provision_called
      end

      test "deprovision! delegates to provisioner" do
        deprovision_called = false
        @sandbox.provisioner.define_singleton_method(:deprovision!) { deprovision_called = true }

        @sandbox.deprovision!

        assert deprovision_called
      end
    end
  end
end
