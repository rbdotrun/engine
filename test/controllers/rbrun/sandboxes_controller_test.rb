# frozen_string_literal: true

require "test_helper"

module Rbrun
  class SandboxesControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    def setup
      super
      @routes = Engine.routes

      # Stub Cloudflare API calls
      stub_request(:get, /api\.cloudflare\.com/)
        .to_return(status: 200, body: { success: true, result: [] }.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "GET /sandboxes renders index" do
      get sandboxes_url
      assert_response :success
    end

    test "GET /sandboxes lists all sandboxes" do
      sandbox = Sandbox.create!
      get sandboxes_url
      assert_response :success
      assert_select "a[href='#{sandbox_path(sandbox)}']"
    end

    test "GET /sandboxes shows repo from config" do
      get sandboxes_url
      assert_response :success
      assert_select "span", text: /#{Rbrun.configuration.git_config.repo}/
    end

    test "POST /sandboxes creates sandbox with one click" do
      assert_difference("Sandbox.count") do
        post sandboxes_url
      end
      assert_redirected_to sandbox_path(Sandbox.last)
    end

    test "POST /sandboxes enqueues provision job" do
      assert_enqueued_with(job: ProvisionSandboxJob) do
        post sandboxes_url
      end
    end

    test "POST /sandboxes generates slug automatically" do
      post sandboxes_url
      sandbox = Sandbox.last
      assert sandbox.slug.present?
    end

    test "POST /sandboxes generates SSH keys automatically" do
      post sandboxes_url
      sandbox = Sandbox.last
      assert sandbox.ssh_public_key.present?
      assert sandbox.ssh_private_key.present?
    end

    test "GET /sandboxes/:id renders show" do
      sandbox = Sandbox.create!
      get sandbox_url(sandbox)
      assert_response :success
    end

    test "GET /sandboxes/:id displays sandbox state" do
      sandbox = Sandbox.create!(state: "running")
      get sandbox_url(sandbox)
      assert_response :success
      assert_select "span", text: /running/
    end

    test "DELETE /sandboxes/:id enqueues deprovision job" do
      sandbox = Sandbox.create!
      assert_enqueued_with(job: DeprovisionSandboxJob) do
        delete sandbox_url(sandbox)
      end
    end

    test "DELETE /sandboxes/:id redirects to show" do
      sandbox = Sandbox.create!
      delete sandbox_url(sandbox)
      assert_redirected_to sandbox_path(sandbox)
    end

    test "POST /sandboxes/:id/toggle_expose requires cloudflare configuration" do
      # Clear cloudflare config
      Rbrun.configuration.cloudflare_config.api_token = nil
      Rbrun.configuration.cloudflare_config.account_id = nil
      Rbrun.configuration.cloudflare_config.domain = nil

      sandbox = Sandbox.create!(exposed: false)
      post toggle_expose_sandbox_url(sandbox)
      assert_redirected_to sandbox_path(sandbox)
      assert_equal "Cloudflare not configured", flash[:alert]
    end

    test "POST /sandboxes/:id/toggle_expose enables exposure when cloudflare configured" do
      # Set cloudflare config
      Rbrun.configuration.cloudflare_config.api_token = "test-key"
      Rbrun.configuration.cloudflare_config.account_id = "test-account"
      Rbrun.configuration.cloudflare_config.domain = "test.dev"

      sandbox = Sandbox.create!(exposed: false)
      post toggle_expose_sandbox_url(sandbox)
      assert_redirected_to sandbox_path(sandbox)
      sandbox.reload
      assert sandbox.exposed?
    end

    test "POST /sandboxes/:id/toggle_expose disables exposure" do
      sandbox = Sandbox.create!(exposed: true)
      post toggle_expose_sandbox_url(sandbox)
      assert_redirected_to sandbox_path(sandbox)
      sandbox.reload
      refute sandbox.exposed?
    end

    private

      def default_url_options
        { host: "localhost" }
      end
  end
end
