# frozen_string_literal: true

require "test_helper"

class RbrunTest < ActiveSupport::TestCase
  test ".configure yields configuration object" do
    Rbrun.reset_configuration!
    yielded = nil
    Rbrun.configure { |c| yielded = c }
    assert_instance_of Rbrun::Configuration, yielded
  end

  test ".configure stores configuration" do
    Rbrun.reset_configuration!
    Rbrun.configure { |c| c.git { |g| g.repo = "test/repo" } }
    assert_equal "test/repo", Rbrun.configuration.git_config.repo
  end

  test ".configuration returns Configuration instance" do
    assert_instance_of Rbrun::Configuration, Rbrun.configuration
  end

  test ".configuration memoizes configuration" do
    config1 = Rbrun.configuration
    config2 = Rbrun.configuration
    assert_same config1, config2
  end

  test ".reset_configuration! creates new configuration instance" do
    old_config = Rbrun.configuration
    Rbrun.reset_configuration!
    new_config = Rbrun.configuration
    refute_same old_config, new_config
  end

  test ".reset_configuration! clears previous settings" do
    Rbrun.configuration.git_config.repo = "test/repo"
    Rbrun.reset_configuration!
    assert_nil Rbrun.configuration.git_config.repo
  end
end
