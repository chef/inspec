# Functional tests related to plugin facility
require "functional/helper"

# I wrapped the whole file in a describe to refactor the include and
# add parallelization. I didn't want to reindent the whole file until
# we know this works well.

# rubocop:disable Layout/IndentationConsistency

describe "plugins" do
  include FunctionalHelper
  parallelize_me!

#=========================================================================================#
#                                Loader Errors
#=========================================================================================#
describe "plugin loader" do
  it "handles an unloadable plugin correctly" do
    outcome = inspec_with_env("version", INSPEC_CONFIG_DIR: File.join(config_dir_path, "plugin_error_on_load"))

    _(outcome.stdout).must_include("ERROR", "Have an error on stdout")
    _(outcome.stdout).must_include("Could not load plugin inspec-divide-by-zero", "Name the plugin in the stdout error")
    _(outcome.stdout).wont_include("ZeroDivisionError", "No stacktrace in error by default")
    _(outcome.stdout).must_include("Errors were encountered while loading plugins", "Friendly message in error")
    _(outcome.stdout).must_include("Plugin name: inspec-divide-by-zero", "Plugin named in error")
    _(outcome.stdout).must_include("divided by 0", "Exception message in error")

    assert_exit_code 2, outcome

    # TODO: split
    outcome = inspec_with_env("version --debug", INSPEC_CONFIG_DIR: File.join(config_dir_path, "plugin_error_on_load"))

    _(outcome.stdout).must_include("ZeroDivisionError", "Include stacktrace in error with --debug")

    assert_exit_code 2, outcome
  end
end

#=========================================================================================#
#                              Disabling Plugins
#=========================================================================================#
describe "when disabling plugins" do
  describe "when disabling the core plugins" do
    it "should not be able to use core-provided commands" do
      run_result = run_inspec_process("--disable-core-plugins habitat")
      _(run_result.stderr).must_include 'Could not find command "habitat".'

      # One might think that this should be code 2 (plugin error)
      # But because the core plugins are not loaded, 'habitat' is not
      # a known command, which makes it a usage error, code 1.
      assert_exit_code 1, run_result
    end
  end

  describe "when disabling the user plugins" do
    it "should not be able to use user commands" do
      run_result = run_inspec_process("--disable-user-plugins meaningoflife answer", env: { INSPEC_CONFIG_DIR: File.join(config_dir_path, "meaning_by_path") })

      _(run_result.stderr).must_include 'Could not find command "meaningoflife"'

      assert_exit_code 1, run_result
    end
  end
end

#=========================================================================================#
#                           CliCommand plugin type
#=========================================================================================#
describe "cli command plugins" do
  it "is able to respond to a plugin-based cli subcommand" do
    outcome = inspec_with_env("meaningoflife answer", INSPEC_CONFIG_DIR: File.join(config_dir_path, "meaning_by_path"))

    _(outcome.stderr).wont_include 'Could not find command "meaningoflife"'
    _(outcome.stderr).must_equal ""

    _(outcome.stdout).must_equal ""

    assert_exit_code 42, outcome
  end

  it "is able to respond to [help subcommand] invocations" do
    outcome = inspec_with_env("help meaningoflife", INSPEC_CONFIG_DIR: File.join(config_dir_path, "meaning_by_path"))

    _(outcome.stderr).must_equal ""

    _(outcome.stdout).must_include "inspec meaningoflife answer"
    # Full text:
    # 'Exits immediately with an exit code reflecting the answer to life the universe, and everything.'
    # but Thor will ellipsify based on the terminal width
    _(outcome.stdout).must_include "Exits immediately"

    assert_exit_code 0, outcome
  end

  # This is an important test; usually CLI plugins are only activated when their name is present in ARGV
  it "includes plugin-based cli commands in top-level help" do
    outcome = inspec_with_env("help", INSPEC_CONFIG_DIR: File.join(config_dir_path, "meaning_by_path"))

    _(outcome.stdout).must_include "inspec meaningoflife"

    assert_exit_code 0, outcome
  end
end

#=========================================================================================#
#                             Input plugin type
#=========================================================================================#
describe "input plugins" do
  let(:env) { { INSPEC_CONFIG_DIR: "#{config_dir_path}/input_plugin" } }
  let(:profile) { "#{profile_path}/inputs/plugin" }
  def run_input_plugin_test_with_controls(controls)
    cmd = "exec #{profile} --controls #{controls}"
    run_result = run_inspec_process(cmd, json: true, env: env)
    _(run_result.stderr).must_be_empty
    assert_json_controls_passing(run_result)
  end

  describe "when an input is provided only by a plugin" do
    it "should find the value" do
      run_input_plugin_test_with_controls("only_in_plugin")
    end
  end

  describe "when an input is provided both inline and by a higher-precedence plugin" do
    it "should use the value from the plugin" do
      run_input_plugin_test_with_controls("collide_plugin_higher")
    end
  end

  describe "when an input is provided both inline and by a lower-precedence plugin" do
    it "should use the value from inline" do
      run_input_plugin_test_with_controls("collide_inline_higher")
    end
  end

  describe "when examining the event log" do
    it "should include the expected events" do
      run_input_plugin_test_with_controls("event_log")
    end
  end

  describe "when listing available inputs" do
    it "should list available inputs" do
      run_input_plugin_test_with_controls("list_events")
    end
  end
end

#=========================================================================================#
#                             Reporter plugin type
#=========================================================================================#
describe "reporter plugins" do
  # The test reporter plugin returns a single line of output, like this:
  # pXX:cYY:tZZ
  # where XX is the count of profiles
  #       YY is the count of controls
  #       ZZ is the count of tests
  let(:env) { { INSPEC_CONFIG_DIR: "#{config_dir_path}/reporter_plugin" } }

  # Test a flat profile - dependencies/profile_c is a simple one
  describe "when using a custom reporter on a profile with one control" do
    it "finds the single control" do
      cmd = "exec #{profile_path}/dependencies/profile_c --reporter test-fixture"
      run_result = run_inspec_process(cmd, env: env)
      _(run_result.stderr).must_be_empty
      _(run_result.stdout).must_include "p1c1t1"
    end
  end
end

#=========================================================================================#
#                           inspec plugin command
#=========================================================================================#
# See lib/plugins/inspec-plugin-manager-cli/test

#=========================================================================================#
#                                Plugin Disable Messaging
#=========================================================================================#
describe "disable plugin usage message integration" do
  it "mentions the --disable-user-plugins option" do
    outcome = inspec("help")
    _(outcome.stdout).must_include("--disable-user-plugins")
  end
end

#=========================================================================================#
#                           DSL Plugin Support
#=========================================================================================#

describe "DSL plugin types support" do
  include PluginFunctionalHelper

  let(:fixture_path) { File.join(profile_path, "dsl_plugins", "controls", profile_file) }
  let(:dsl_plugin_path) { File.join(mock_path, "plugins", "inspec-dsl-test", "lib", "inspec-dsl-test.rb") }
  let(:run_result) { run_inspec_with_plugin("exec #{fixture_path}", plugin_path: dsl_plugin_path) }

  describe "outer profile dsl plugin type support" do
    let(:profile_file) { "outer_profile_dsl.rb" }
    it "works correctly with outer_profile dsl extensions" do
      _(run_result.stderr).must_equal ""

      # The outer_profile_dsl.rb file has control-01, then a call to favorite_grain
      # (which generates a control), then control-03.
      # If the plugin exploded, we'd see control-01 but not control-03
      controls = @json["profiles"][0]["controls"]
      _(controls.count).must_equal 3

      # We expect the second controls id to be 'sorghum'
      # (this is the functionality of the outer_profile_dsl we installed)
      generated_control = @json["profiles"][0]["controls"][1]
      _(generated_control["id"]).must_equal "sorghum"
      _(generated_control["results"][0]["status"]).must_equal "passed"
    end
  end

  describe "control dsl plugin type support" do

    let(:profile_file) { "control_dsl.rb" }
    it "works correctly with control dsl extensions" do
      _(run_result.stderr).must_equal ""

      # The control_dsl.rb file has one control, with a describe-01, then a call to favorite_fruit, then describe-02
      # If the plugin exploded, we'd see describe-01 but not describe-02
      results = @json["profiles"][0]["controls"][0]["results"]
      _(results.count).must_equal 2

      # We expect the descriptions to include that the favorite fruit is banana
      # (this is the functionality of the control_dsl we installed)
      first_description_section = @json["profiles"][0]["controls"][0]["descriptions"].first
      _(first_description_section).wont_be_nil
      _(first_description_section["label"]).must_equal "favorite_fruit"
      _(first_description_section["data"]).must_equal "Banana"
    end
  end

  describe "describe dsl plugin type support" do
    let(:profile_file) { "describe_dsl.rb" }
    it "works correctly with describe dsl extensions" do
      _(run_result.stderr).must_equal ""

      # The describe_dsl.rb file has one control, with
      # describe-01, describe-02 which contains a call to favorite_vegetable, then describe-03
      # If the plugin exploded, we'd see describe-01 but not describe-02
      results = @json["profiles"][0]["controls"][0]["results"]
      _(results.count).must_equal 3

      # We expect the description of describe-02 to include the word aubergine
      # (this is the functionality of the describe_dsl we installed)
      second_result = @json["profiles"][0]["controls"][0]["results"][1]
      _(second_result).wont_be_nil
      _(second_result["code_desc"]).must_include "aubergine"
    end
  end

  describe "test dsl plugin type support" do
    let(:profile_file) { "test_dsl.rb" }
    it "works correctly with test dsl extensions" do
      _(run_result.stderr).must_equal ""

      # The test_dsl.rb file has one control, with
      # describe-01, describe-02 which contains a call to favorite_legume, then describe-03
      # If the plugin exploded, we'd see describe-01 but not describe-02
      results = @json["profiles"][0]["controls"][0]["results"]
      _(results.count).must_equal 3

      # I spent a while trying to find a way to get the test to alter its name;
      # that won't work for various setup reasons.
      # So, it just throws an exception with the word 'edemame' in it.
      second_result = @json["profiles"][0]["controls"][0]["results"][1]
      _(second_result).wont_be_nil
      _(second_result["status"]).must_equal "failed"
      _(second_result["message"]).must_include "edemame"
    end
  end

  describe "resource dsl plugin type support" do
    let(:profile_file) { "unused" }
    it "works correctly with test dsl extensions" do
      # We have to build a custom command line - need to load the whole profile,
      # so the libraries get loaded.
      cmd = "exec "
      cmd += File.join(profile_path, "dsl_plugins")
      cmd += " --controls=/^rdsl-control/ "
      run_result = run_inspec_with_plugin(cmd, plugin_path: dsl_plugin_path)
      _(run_result.stderr).must_equal ""

      # We should have three controls; 01 and 03 just do a string match.
      # 02 uses the custom resource, which relies on calls to the resource DSL.
      # If the plugin exploded, we'd see rdsl-control-01 but not rdsl-control-02
      results = @json["profiles"][0]["controls"]
      _(results.count).must_equal 3

      # Control 2 has 2 describes; one uses a simple explicit matcher,
      # while the second uses a matcher defined via a macro provided by the resource DSL.
      control2_results = results[1]["results"]
      _(control2_results[0]["status"]).must_equal "passed"
      _(control2_results[0]["code_desc"]).must_include "favorite_berry"
      _(control2_results[0]["code_desc"]).must_include "blendable"

      _(control2_results[1]["status"]).must_equal "passed"
      _(control2_results[1]["code_desc"]).must_include "favorite_berry"
      _(control2_results[1]["code_desc"]).must_include "have drupals"
    end
  end
end

#=========================================================================================#
#                           Train Plugin Support
#=========================================================================================#

describe "train plugin support" do
  describe "when a train plugin is installed" do
    it "can run inspec detect against a URL target" do
      outcome = inspec_with_env("detect -t test-fixture://", INSPEC_CONFIG_DIR: File.join(config_dir_path, "train-test-fixture"))
      _(outcome.stderr).must_be_empty

      lines = outcome.stdout.split("\n")
      _(lines.grep(/Name/).first).must_include("test-fixture")
      _(lines.grep(/Name/).first).wont_include("train-test-fixture")
      _(lines.grep(/Release/).first).must_include("0.1.0")
      _(lines.grep(/Families/).first).must_include("os")
      _(lines.grep(/Families/).first).must_include("windows")
      _(lines.grep(/Families/).first).must_include("unix")
      _(lines.grep(/Arch/).first).must_include("mock")

      assert_exit_code 0, outcome
    end

    it "can run inspec detect against a test-fixture backend" do
      outcome = inspec_with_env("detect -b test-fixture", INSPEC_CONFIG_DIR: File.join(config_dir_path, "train-test-fixture"))
      _(outcome.stderr).must_be_empty

      lines = outcome.stdout.split("\n")
      _(lines.grep(/Name/).first).must_include("test-fixture")
      _(lines.grep(/Name/).first).wont_include("train-test-fixture")
      _(lines.grep(/Release/).first).must_include("0.1.0")
      _(lines.grep(/Families/).first).must_include("os")
      _(lines.grep(/Families/).first).must_include("windows")
      _(lines.grep(/Families/).first).must_include("unix")
      _(lines.grep(/Arch/).first).must_include("mock")

      assert_exit_code 0, outcome
    end

    it "can run inspec shell and read a file" do
      # The test fixture always returns the same content regardless of path
      outcome = inspec_with_env("shell -t test-fixture:// -c 'file(%q{/opt/any-path}).content'", INSPEC_CONFIG_DIR: File.join(config_dir_path, "train-test-fixture"))
      _(outcome.stderr).must_be_empty

      _(outcome.stdout.chomp).must_equal "Lorem Ipsum"

      assert_exit_code 0, outcome
    end

    it "can run inspec shell and run a command" do
      # The test fixture always returns the same stdout and the same exit code.
      outcome = inspec_with_env("shell -t test-fixture:// -c 'command(%q{echo hello}).exit_status'", INSPEC_CONFIG_DIR: File.join(config_dir_path, "train-test-fixture"))
      _(outcome.stderr).must_be_empty

      _(outcome.stdout.chomp).must_equal "17"

      assert_exit_code 0, outcome

      # TODO: split
      outcome = inspec_with_env("shell -t test-fixture:// -c 'command(%q{echo hello}).stdout'", INSPEC_CONFIG_DIR: File.join(config_dir_path, "train-test-fixture"))

      _(outcome.stderr).must_be_empty

      _(outcome.stdout.chomp).must_equal "Mock Command Result stdout"

      assert_exit_code 0, outcome
    end
  end
end

end
