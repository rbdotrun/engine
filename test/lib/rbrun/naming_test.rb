# frozen_string_literal: true

require "test_helper"

module Rbrun
  class NamingTest < ActiveSupport::TestCase
    VALID_SLUG = "a1b2c3"
    INVALID_SLUGS = [
      nil,
      "",
      "abc",           # too short (3 chars)
      "abcde",         # too short (5 chars)
      "a1b2c3d",       # too long (7 chars)
      "a1b2c3d4",      # too long (8 chars)
      "ABCDEF",        # uppercase not allowed
      "a1b2cg",        # 'g' not valid hex
      "a1b2c!",        # special char
      "a1 b2c",        # space
      12345,           # integer (5 digits - invalid length)
      "a1b2c3\n"       # newline
    ].freeze

    # ─────────────────────────────────────────────────────────────
    # Constants
    # ─────────────────────────────────────────────────────────────

    test "PREFIX constant is rbrun-sandbox" do
      assert_equal "rbrun-sandbox", Naming::PREFIX
    end

    test "SLUG_LENGTH constant is 6" do
      assert_equal 6, Naming::SLUG_LENGTH
    end

    test "SLUG_REGEX matches 6 hex chars" do
      assert_match Naming::SLUG_REGEX, "a1b2c3"
      assert_match Naming::SLUG_REGEX, "000000"
      assert_match Naming::SLUG_REGEX, "ffffff"
      assert_no_match Naming::SLUG_REGEX, "abcde"
      assert_no_match Naming::SLUG_REGEX, "abcdefg"
      assert_no_match Naming::SLUG_REGEX, "ABCDEF"
    end

    # ─────────────────────────────────────────────────────────────
    # Slug Generation & Validation
    # ─────────────────────────────────────────────────────────────

    test ".generate_slug returns 6 hex chars" do
      slug = Naming.generate_slug
      assert_equal 6, slug.length
      assert_match(/\A[a-f0-9]{6}\z/, slug)
    end

    test ".generate_slug returns unique values" do
      slugs = 100.times.map { Naming.generate_slug }
      assert_equal 100, slugs.uniq.size
    end

    test ".valid_slug? returns true for valid slug" do
      assert Naming.valid_slug?(VALID_SLUG)
    end

    test ".valid_slug? returns false for invalid slugs" do
      INVALID_SLUGS.each do |invalid|
        assert_not Naming.valid_slug?(invalid), "Expected #{invalid.inspect} to be invalid"
      end
    end

    test ".validate_slug! does not raise for valid slug" do
      assert_nothing_raised { Naming.validate_slug!(VALID_SLUG) }
    end

    test ".validate_slug! raises ArgumentError for invalid slugs" do
      INVALID_SLUGS.each do |invalid|
        error = assert_raises(ArgumentError) { Naming.validate_slug!(invalid) }
        assert_match(/Invalid slug format/, error.message)
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Static Methods (no slug validation)
    # ─────────────────────────────────────────────────────────────

    test ".default_user returns deploy" do
      assert_equal "deploy", Naming.default_user
    end

    test ".auth_cookie returns prefixed cookie name" do
      assert_equal "rbrun-sandbox-auth", Naming.auth_cookie
    end

    # ─────────────────────────────────────────────────────────────
    # Resource Naming (with validation)
    # ─────────────────────────────────────────────────────────────

    test ".resource returns prefixed resource name" do
      assert_equal "rbrun-sandbox-a1b2c3", Naming.resource(VALID_SLUG)
    end

    test ".resource raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.resource("invalid") }
    end

    test ".resource_regex extracts slug from resource name" do
      match = "rbrun-sandbox-a1b2c3".match(Naming.resource_regex)
      assert_not_nil match
      assert_equal "a1b2c3", match[1]
    end

    test ".resource_regex does not match invalid names" do
      assert_no_match Naming.resource_regex, "sandbox-123"
      assert_no_match Naming.resource_regex, "rbrun-a1b2c3"
      assert_no_match Naming.resource_regex, "other-prefix-a1b2c3"
    end

    # ─────────────────────────────────────────────────────────────
    # Container Naming
    # ─────────────────────────────────────────────────────────────

    test ".container returns prefixed container name with role" do
      assert_equal "rbrun-sandbox-a1b2c3-app", Naming.container(VALID_SLUG, "app")
      assert_equal "rbrun-sandbox-a1b2c3-tunnel", Naming.container(VALID_SLUG, "tunnel")
    end

    test ".container raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.container("invalid", "app") }
    end

    # ─────────────────────────────────────────────────────────────
    # Git Branch Naming
    # ─────────────────────────────────────────────────────────────

    test ".branch returns prefixed branch name" do
      assert_equal "rbrun-sandbox/a1b2c3", Naming.branch(VALID_SLUG)
    end

    test ".branch raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.branch("invalid") }
    end

    # ─────────────────────────────────────────────────────────────
    # Hostname & URL Naming
    # ─────────────────────────────────────────────────────────────

    test ".hostname returns prefixed hostname" do
      assert_equal "rbrun-sandbox-a1b2c3.rb.run", Naming.hostname(VALID_SLUG, "rb.run")
    end

    test ".hostname raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.hostname("invalid", "rb.run") }
    end

    test ".hostname_regex extracts slug from hostname" do
      match = "rbrun-sandbox-a1b2c3.rb.run".match(Naming.hostname_regex)
      assert_not_nil match
      assert_equal "a1b2c3", match[1]
    end

    test ".self_hosted_preview_url returns https URL" do
      assert_equal "https://rbrun-sandbox-a1b2c3.rb.run", Naming.self_hosted_preview_url(VALID_SLUG, "rb.run")
    end

    test ".self_hosted_preview_url raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.self_hosted_preview_url("invalid", "rb.run") }
    end

    # ─────────────────────────────────────────────────────────────
    # Worker Naming
    # ─────────────────────────────────────────────────────────────

    test ".worker returns prefixed worker name" do
      assert_equal "rbrun-sandbox-widget-a1b2c3", Naming.worker(VALID_SLUG)
    end

    test ".worker raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.worker("invalid") }
    end

    test ".worker_regex extracts slug from worker name" do
      match = "rbrun-sandbox-widget-a1b2c3".match(Naming.worker_regex)
      assert_not_nil match
      assert_equal "a1b2c3", match[1]
    end

    test ".worker_route returns prefixed route pattern" do
      assert_equal "rbrun-sandbox-a1b2c3.rb.run/*", Naming.worker_route(VALID_SLUG, "rb.run")
    end

    test ".worker_route raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.worker_route("invalid", "rb.run") }
    end

    # ─────────────────────────────────────────────────────────────
    # SSH & Database Naming
    # ─────────────────────────────────────────────────────────────

    test ".ssh_comment returns prefixed comment" do
      assert_equal "rbrun-sandbox-a1b2c3", Naming.ssh_comment(VALID_SLUG)
    end

    test ".ssh_comment raises for invalid slug" do
      assert_raises(ArgumentError) { Naming.ssh_comment("invalid") }
    end

    # ─────────────────────────────────────────────────────────────
    # Roundtrip Tests (generate -> use -> extract)
    # ─────────────────────────────────────────────────────────────

    test "generated slug can be used in all naming methods" do
      slug = Naming.generate_slug

      # All these should work without raising
      assert_nothing_raised do
        Naming.resource(slug)
        Naming.container(slug, "app")
        Naming.branch(slug)
        Naming.hostname(slug, "rb.run")
        Naming.self_hosted_preview_url(slug, "rb.run")
        Naming.worker(slug)
        Naming.worker_route(slug, "rb.run")
        Naming.ssh_comment(slug)
      end
    end

    test "slug can be extracted from resource name and reused" do
      original_slug = Naming.generate_slug
      resource_name = Naming.resource(original_slug)

      extracted = resource_name.match(Naming.resource_regex)[1]
      assert_equal original_slug, extracted

      # Extracted slug should work for other naming methods
      assert_equal Naming.worker(original_slug), Naming.worker(extracted)
    end
  end
end
