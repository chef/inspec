require "functional/helper"

describe "inspec exec" do
  parallelize_me!

  include FunctionalHelper
  let(:looks_like_a_stacktrace) { %r{lib/inspec/.+\.rb:\d+:in} }

  attr_accessor :out

  def inspec(commandline, prefix = nil)
    @stdout = @stderr = nil
    self.out = super
  end

  def stdout
    @stdout ||= out.stdout
      .force_encoding(Encoding::UTF_8)
      .gsub(/\e\[(\d+)(;\d+)*m/, "") # strip ANSI color codes
  end

  def stderr
    @stderr ||= out.stderr
      .force_encoding(Encoding::UTF_8)
      .gsub(/\e\[(\d+)(;\d+)*m/, "") # strip ANSI color codes
  end

  before do
    prof = "test/fixtures/profiles"
    FileUtils.rm_f "#{prof}/aws-profile/inspec.lock"
    FileUtils.rm_f "#{prof}/simple-inheritance/inspec.lock"
    FileUtils.rm_f "#{prof}/simple-metadata/inspec.lock"
  end

  it "handles '=' character on input" do
    # This test handles a bug discovered at: https://github.com/inspec/inspec/issues/5131
    inspec(
      "exec " +
      File.join(profile_path, "inputs", "with_various_values") +
      " --no-create-lockfile" +
      " --input my_input='ab=cde'"
    )

    _(stdout).must_include "0 failures"
  end

  it "cleanly fails if mixing incompatible resource and transports" do
    # TODO: It should be possible to test this more directly.
    inspec "exec -t aws:// #{profile_path}/incompatible_resource_for_transport.rb"

    _(stderr).must_be_empty
    _(stdout).must_include "Unsupported resource/backend combination: file / aws. Exiting."
    assert_exit_code 100, out
  end

  it "can execute the profile" do
    inspec("exec " + complete_profile + " --no-create-lockfile")

    _(stdout).must_include "Host example.com"
    _(stdout).must_include "1 successful control, "\
      "0 control failures, 0 controls skipped"
    _(stderr).must_be_empty

    assert_exit_code 0, out
  end

  it "executes a minimum metadata-only profile" do
    inspec("exec " + File.join(profile_path, "simple-metadata") + " --no-create-lockfile")

    _(stdout).must_equal "
Profile: yumyum profile
Version: (not specified)
Target:  local://

     No tests executed.

Test Summary: 0 successful, 0 failures, 0 skipped
"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "can execute the profile and write to directory" do
    outpath = Dir.tmpdir
    inspec("exec #{complete_profile} --no-create-lockfile --reporter json:#{outpath}/foo/bar/test.json")

    _(File.exist?("#{outpath}/foo/bar/test.json")).must_equal true
    _(File.stat("#{outpath}/foo/bar/test.json").size).must_be :>, 0

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "can execute --help after exec command" do
    inspec("exec --help")

    _(stdout).must_include "Usage:\n  inspec exec LOCATIONS"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "can execute help after exec command" do
    inspec("exec help")

    _(stdout).must_include "Usage:\n  inspec exec LOCATIONS"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "can execute help before exec command" do
    inspec("help exec")

    _(stdout).must_include "Usage:\n  inspec exec LOCATIONS"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "can execute the profile with a target_id passthrough" do
    inspec("exec #{complete_profile} --no-create-lockfile --target-id 1d3e399f-4d71-4863-ac54-84d437fbc444")

    _(stdout).must_include "Target ID: 1d3e399f-4d71-4863-ac54-84d437fbc444"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes a metadata-only profile" do
    inspec("exec " + File.join(profile_path, "complete-metadata") + " --no-create-lockfile")

    _(stdout).must_equal "
Profile: title (name)
Version: 1.2.3
Target:  local://

     No tests executed.

Test Summary: 0 successful, 0 failures, 0 skipped
"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes a profile and reads inputs" do
    inspec("exec #{File.join(examples_path, "profile-attribute")} --no-create-lockfile --input-file #{File.join(examples_path, "profile-attribute.yml")}")

    _(stdout).must_include "Test Summary: 2 successful, 0 failures, 0 skipped"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes a specs-only profile" do
    inspec("exec " + File.join(profile_path, "spec_only") + " --no-create-lockfile")

    _(stdout).must_include "Target:  local://"
    _(stdout).must_include "working"
    _(stdout).must_include "✔  is expected to eq \"working\""
    _(stdout).must_include "skippy\n"
    _(stdout).must_include "↺  This will be skipped intentionally"
    _(stdout).must_include "failing"
    _(stdout).must_include "×  is expected to eq \"as intended\""
    _(stdout).must_include "Test Summary: 1 successful, 1 failure, 1 skipped\n"

    _(stderr).must_equal ""

    assert_exit_code 100, out
  end

  it "executes only specified controls when selecting the controls by literal names" do
    inspec("exec " + File.join(profile_path, "controls-option-test") + " --no-create-lockfile --controls foo")
    _(out.stdout).must_include "foo"
    _(out.stdout).wont_include "bar"
    _(out.stdout).wont_include "only-describe"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting the controls by regex" do
    inspec("exec " + File.join(profile_path, "controls-option-test") + " --no-create-lockfile --controls '/^11_pass/'")
    _(out.stdout).must_include "11_pass"
    _(out.stdout).must_include "11_pass2"
    _(out.stdout).wont_include "bar"
    _(out.stdout).wont_include "only-describe"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting passing controls by literal names" do
    inspec("exec " + File.join(profile_path, "filter_table") + " --no-create-lockfile --controls 2943_pass_undeclared_field_in_hash 2943_pass_irregular_row_key")

    _(stdout).must_include "\nProfile Summary: 2 successful controls, 0 control failures, 0 controls skipped\n"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting failing controls by literal names" do
    inspec("exec " + File.join(profile_path, "filter_table") + " --no-create-lockfile --controls 2943_fail_derail_check")

    _(stdout).must_include "\nProfile Summary: 0 successful controls, 1 control failure, 0 controls skipped"

    _(stderr).must_equal ""

    assert_exit_code 100, out
  end

  it "executes only specified controls when selecting passing controls by regex" do
    inspec("exec " + File.join(profile_path, "filter_table") + " --no-create-lockfile --controls '/^2943_pass/'")

    _(stdout).must_include "Profile Summary: 6 successful controls, 0 control failures, 0 controls skipped"

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting failing controls by regex" do
    inspec("exec " + File.join(profile_path, "filter_table") + " --no-create-lockfile --controls '/^2943_fail/'")

    _(stdout).must_include "Profile Summary: 0 successful controls, 1 control failure, 0 controls skipped"

    _(stderr).must_equal ""

    assert_exit_code 100, out
  end

  it "executes only specified controls when selecting the controls by literal single tag name" do
    inspec("exec " + File.join(profile_path, "control-tags") + " --no-create-lockfile --tags tag1")
    _(stdout).must_include "true is expected to eq true\n"
    _(stdout).must_include "Test Summary: 1 successful, 0 failures, 0 skipped\n"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting the controls by literal multiple tag names" do
    inspec("exec " + File.join(profile_path, "control-tags") + " --no-create-lockfile --tags tag1 tag5 tag6 tag17 'tagname with space'")
    _(stdout).must_include "true is expected to eq true\n"
    _(stdout).must_include "Test Summary: 4 successful, 0 failures, 0 skipped\n"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting the controls by using regex on tags" do
    inspec("exec " + File.join(profile_path, "control-tags") + " --no-create-lockfile --tags '/\s+/'")
    _(stdout).must_include "true is expected to eq true\n"
    _(stdout).must_include "Test Summary: 1 successful, 0 failures, 0 skipped\n"
    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "executes only specified controls when selecting failing controls by using literal name of tag" do
    inspec("exec " + File.join(profile_path, "control-tags") + " --no-create-lockfile --tags tag18")
    _(stdout).must_include "true is expected to eq false\n"
    _(stdout).must_include "Test Summary: 0 successful, 1 failure, 0 skipped\n"
    _(stderr).must_equal ""

    assert_exit_code 100, out
  end

  it "executes only specified controls when selecting failing controls by using regex on tags" do
    inspec("exec " + File.join(profile_path, "control-tags") + " --no-create-lockfile --tags '/(18)/'")
    _(stdout).must_include "true is expected to eq false\n"
    _(stdout).must_include "Test Summary: 0 successful, 1 failure, 0 skipped\n"
    _(stderr).must_equal ""

    assert_exit_code 100, out
  end

  it "reports whan a profile cannot be loaded" do
    inspec("exec " + File.join(profile_path, "raise_outside_control") + " --no-create-lockfile")
    _(stdout).must_match(/Profile:[\W]+InSpec Profile \(raise_outside_control\)/)

    _(stdout).must_include "ERROR: Failed to load profile raise_outside_control: Failed to load source for controls/raises.rb: Something unforeseen..."

    assert_exit_code 102, out
  end

  it "can execute a simple file with the default formatter" do
    inspec("exec " + example_control + " --no-create-lockfile")

    _(stdout).must_include "\nProfile Summary: 1 successful control, 0 control failures, 0 controls skipped\n"
    _(stdout).must_include "\nTest Summary: 2 successful, 0 failures, 0 skipped\n"

    _(stderr).must_equal ""

    assert_exit_code 0, out
  end

  it "does not vendor profiles when using the a local path dependecy" do
    Dir.mktmpdir do |tmpdir|
      command = "exec " + inheritance_profile + " --no-create-lockfile " \
        "--input-file=#{examples_path}/profile-attribute.yml"
      inspec_with_env(command, INSPEC_CONFIG_DIR: tmpdir)

      if is_windows?
        _(stdout).must_include "No tests executed."
        assert_exit_code 1, out
      else
        _(stdout).must_include "Profile Summary: 2 successful controls, 0 control failures, 0 controls skipped\n"
        _(stdout).must_include "Test Summary: 5 successful, 0 failures, 0 skipped\n"
        assert_exit_code 0, out
      end

      cache_dir = File.join(tmpdir, "cache")
      _(Dir.exist?(cache_dir)).must_equal true
      _(Dir.glob(File.join(cache_dir, "**", "*"))).must_be_empty

      _(stderr).must_equal ""
    end
  end

  describe "with a profile that is not supported on this OS/platform" do
    let(:out) { inspec("exec " + File.join(profile_path, "skippy-profile-os") + " --no-create-lockfile") }
    let(:json) { JSON.load(stdout) }

    it "exits with skip message" do
      _(stdout).must_include("Skipping profile: 'skippy' on unsupported platform:")

      _(stderr).must_equal ""

      assert_exit_code 101, out
    end
  end

  describe "with a profile that contains skipped controls" do
    let(:out) { inspec("exec " + File.join(profile_path, "skippy-controls") + " --no-create-lockfile") }
    let(:json) { JSON.load(stdout) }

    it "exits with an error" do
      _(stdout).must_include "skippy\n     ↺  This will be skipped super intentionally.\n"
      _(stdout).must_include "Profile Summary: 0 successful controls, 0 control failures, 1 control skipped\nTest Summary: 0 successful, 0 failures, 1 skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 101, out
    end
  end

  describe "with a profile that contains skipped controls and the --no-distinct-exit flag" do
    let(:out) { inspec("exec " + File.join(profile_path, "skippy-controls") + " --no-distinct-exit --no-create-lockfile") }

    it "exits with code 0 and skipped tests in output" do
      _(stdout).must_include "Profile Summary: 0 successful controls, 0 control failures, 1 control skipped\nTest Summary: 0 successful, 0 failures, 1 skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "with a profile that contains failing controls and the --no-distinct-exit flag" do
    let(:out) { inspec("exec " + File.join(profile_path, "failures") + " --no-distinct-exit --no-create-lockfile") }

    it "exits with code 1" do
      _(stdout).must_include "Profile Summary: 0 successful controls, 4 control failures, 0 controls skipped"

      _(stderr).must_equal ""

      assert_exit_code 1, out
    end
  end

  describe "with a profile that contains skipped resources" do
    let(:out) { inspec("exec " + File.join(profile_path, "aws-profile")) }
    it "exits with an error" do
      skip if ENV["NO_AWS"]
      _(stdout).must_include "Unsupported resource/backend combination: aws_iam_users"
      _(stdout).must_include "Unsupported resource/backend combination: aws_iam_access_keys"
      _(stdout).must_include "Unsupported resource/backend combination: aws_s3_bucket"
      _(stdout).must_include "3 failures"

      assert_exit_code 100, out
    end
  end

  describe "with a profile that is supported on this version of inspec" do
    let(:out) { inspec("exec " + File.join(profile_path, "supported_inspec") + " --no-create-lockfile") }

    it "exits cleanly" do
      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "with a profile that is not supported on this version of inspec" do
    let(:out) { inspec("exec " + File.join(profile_path, "unsupported_inspec") + " --no-create-lockfile") }

    it "does not support this profile" do
      _(stderr).must_equal "This profile requires Chef InSpec version >= 99.0.0. You are running Chef InSpec v#{Inspec::VERSION}.\n"

      assert_exit_code 1, out
    end
  end

  describe "with a profile that loads a library and reference" do
    let(:out) { inspec("exec " + File.join(profile_path, "library") + " --no-create-lockfile") }

    it "executes the profile without error" do
      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "given a profile with controls and anonymous describe blocks" do
    let(:out) { inspec("exec " + example_control + " --no-create-lockfile") }

    it "prints the control results, then the anonymous describe block results" do
      _(stdout).must_match(/Profile: tests from .*test.fixtures.profiles.old-examples.profile.controls.example-tmp.rb/)
      _(stdout).must_include "
Version: (not specified)
Target:  local://

  \xE2\x9C\x94  tmp-1.0: Create / directory
     \xE2\x9C\x94  File / is expected to be directory

  File /
     \xE2\x9C\x94  is expected to be directory

Profile Summary: 1 successful control, 0 control failures, 0 controls skipped
Test Summary: 2 successful, 0 failures, 0 skipped\n"
    end
  end

  describe "given a profile with an anonymous describe block" do
    let(:out) { inspec("exec " + failure_control + " --no-create-lockfile") }

    it "prints the exception message when a test has a syntax error" do
      _(stdout).must_include "undefined method `should_nota' "
    end
  end

  describe "given an inherited profile that has more that one test per control block" do
    let(:out) { inspec("exec " + simple_inheritance + " --no-create-lockfile") }

    it "should print all the results" do
      _(stdout).must_include "×  tmp-1.0: Create / directory (1 failed)"
      _(stdout).must_include "×  is expected not to be directory\n"
      _(stdout).must_include "×  File / \n     undefined method `should_nota'"
      _(stdout).must_include "×  is expected not to be directory\n     expected `File /.directory?` to be falsey, got true"
      _(stdout).must_include "×  7 is expected to cmp >= 9\n"
      _(stdout).must_include "×  7 is expected not to cmp == /^\\d$/\n"
      _(stdout).must_include "✔  7 is expected to cmp == \"7\""
      _(stdout).must_include "expected: %s" % ["01147"]
      _(stdout).must_include "got: %s" % [is_windows? ? "040755" : "0755"]
    end
  end

  describe "when passing in two profiles given an inherited profile that has more that one test per control block" do
    let(:out) { inspec("exec " + File.join(profile_path, "dependencies", "profile_d") + " " + simple_inheritance + " --no-create-lockfile") }

    it "should print all the results" do
      _(stdout).must_include "×  tmp-1.0: Create / directory (1 failed)"
      _(stdout).must_include "×  cmp-1.0: Using the cmp matcher for numbers (2 failed)"
      _(stdout).must_include "×  File / \n     undefined method `should_nota'"
      _(stdout).must_include "×  is expected not to be directory\n     expected `File /.directory?` to be falsey, got true"
      _(stdout).must_include "✔  profiled-1: Create / directory (profile d)"
    end
  end

  describe "given an inherited profile" do
    let(:out) { inspec("exec " + simple_inheritance) }

    it "should print the profile information and then the test results" do
      _(stdout).must_include "  ×  tmp-1.0: Create / directory (1 failed)\n     ✔  File / is expected to be directory\n     ×  File / is expected not to be directory\n"
    end
  end

  describe "using namespaced resources" do
    it "works" do
      inspec("exec " + File.join(profile_path, "dependencies", "resource-namespace") + " --no-create-lockfile")

      _(stdout).must_include "Profile Summary: 1 successful control, 0 control failures, 0 controls skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "with require_controls" do
    it "does not run rules you did not include" do
      inspec("exec " + File.join(profile_path, "dependencies", "require_controls_test") + " --no-create-lockfile")

      _(stdout).must_include "Profile Summary: 1 successful control, 0 control failures, 0 controls skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "with a 2-level dependency tree" do
    it "correctly runs tests from the whole tree" do
      inspec("exec " + File.join(profile_path, "dependencies", "inheritance") + " --no-create-lockfile")

      _(stdout).must_include "Profile Summary: 6 successful controls, 0 control failures, 0 controls skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "when using profiles on the supermarket" do
    it "can run supermarket profiles directly from the command line" do

      skip_windows! # Breakage confirmed, only on CI: https://buildkite.com/chef-oss/inspec-inspec-master-verify/builds/2355#2c9d032e-4a24-4e7c-aef2-1c9e2317d9e2
      inspec("exec supermarket://nathenharvey/tmp-compliance-profile --no-create-lockfile")

      if is_windows?
        _(stdout).must_include "Profile Summary: 1 successful control, 1 control failure, 0 controls skipped\n"
      else
        _(stdout).must_include "Profile Summary: 2 successful controls, 0 control failures, 0 controls skipped\n"
      end

      _(stderr).must_equal ""

      if is_windows?
        assert_exit_code 100, out # references root
      else
        assert_exit_code 0, out
      end
    end

    it "can run supermarket profiles from inspec.yml" do
      skip_windows! # Breakage confirmed, only on CI: https://buildkite.com/chef-oss/inspec-inspec-master-verify/builds/2355#2c9d032e-4a24-4e7c-aef2-1c9e2317d9e2

      inspec("exec #{File.join(profile_path, "supermarket-dep")} --no-create-lockfile")

      if is_windows?
        _(stdout).must_include "Profile Summary: 1 successful control, 1 control failure, 0 controls skipped\n"
      else
        _(stdout).must_include "Profile Summary: 2 successful controls, 0 control failures, 0 controls skipped\n"
      end

      _(stderr).must_equal ""

      if is_windows?
        assert_exit_code 1, out
      else
        assert_exit_code 0, out
      end
    end
  end

  describe "when a dependency does not support our backend platform" do
    it "skips the controls from that profile" do
      inspec("exec #{File.join(profile_path, "profile-support-skip")} --no-create-lockfile")

      _(stdout).must_include "WARN: Skipping profile"
      _(stdout).must_include "0 successful, 0 failures, 0 skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "when trying to use --sudo with a local target" do
    it "must print an error and exit" do
      inspec("exec #{File.join(profile_path, "profile-support-skip")} --sudo")
      str = "Sudo is only valid when running against a remote host. To run this locally with elevated privileges, run the command with `sudo ...`.\n"

      _(stderr).must_include str

      assert_exit_code 1, out
      # TODO: check for stacktrace
    end
  end

  describe "when --no-color is used" do
    it "does not output color control characters" do
      inspec("exec " + File.join(profile_path, "simple-metadata") + " --no-color")

      _(stdout).wont_include "\e[38"

      _(stderr).must_equal ""

      assert_exit_code 0, out
    end
  end

  describe "when --password is used" do
    it "raises an exception if no password is provided" do
      inspec("exec " + complete_profile + " --password")

      _(stderr).must_include "Please provide a value for --password. For example: --password=hello."

      assert_exit_code 1, out
    end
  end

  describe "when --sudo-password is used" do
    it "raises an exception if no sudo password is provided" do
      inspec("exec " + complete_profile + " --sudo-password")

      _(stderr).must_include "Please provide a value for --sudo-password. For example: --sudo-password=hello."

      assert_exit_code 1, out
    end
  end

  describe "when --bastion-host and --proxy_command is used" do
    it "raises an exception when both flags are provided" do
      inspec("exec " + complete_profile + " -t ssh://dummy@dummy --password dummy --proxy_command dummy --bastion_host dummy")

      _(stderr).must_include "Client error, can't connect to 'ssh' backend: Only one of proxy_command or bastion_host needs to be specified"

      assert_exit_code 1, out
    end
  end

  describe "when --winrm-transport is used" do
    it "raises an exception when an invalid transport is given" do
      inspec("exec " + complete_profile + " -t winrm://administrator@dummy --password dummy --winrm-transport nonesuch")

      _(stderr).must_include "Client error, can't connect to 'winrm' backend: Unsupported transport type: :nonesuch\n"

      assert_exit_code 1, out
    end
  end

  describe "with sensitive resources" do
    it "hides sensitive output" do
      inspec("exec " + sensitive_profile + " --no-create-lockfile")

      _(stdout).must_include '×  is expected to eq "billy"'
      _(stdout).must_include 'expected: "billy"'
      _(stdout).must_include 'got: "bob"'
      _(stdout).must_include '×  is expected to eq "secret"'
      _(stdout).must_include "*** sensitive output suppressed ***"
      _(stdout).must_include "\nTest Summary: 2 successful, 2 failures, 0 skipped\n"

      _(stderr).must_equal ""

      assert_exit_code 100, out
    end
  end

  describe "with a profile that loads dependencies" do
    let(:out) { inspec("exec " + File.join(profile_path, "profile-support-skip") + " --no-create-lockfile --reporter json") }
    let(:json) { JSON.load(stdout) }
    let(:controls) { json["profiles"][0]["controls"] }

    it "skips loaded inherited profiles on unsupported platforms" do
      _(json["profiles"][0]["depends"][0]["name"]).must_equal "unsupported_inspec"
      _(controls).must_be_empty

      _(stderr).must_include "WARN: Skipping profile"
    end
  end

  describe "with a profile containing exceptions in the controls" do
    let(:out) { inspec("exec " + File.join(profile_path, "exception-in-control") + " --no-create-lockfile --reporter json") }
    let(:json) { JSON.load(stdout) }
    let(:controls) { json["profiles"][0]["controls"] }

    it "completes the run with failed controls but no exception" do
      _(stderr).must_be_empty

      _(controls.count).must_equal 10
      _(controls.select { |c| c["results"][0]["status"] == "failed" }.count).must_be :>, 1
      _(controls.select { |c| c["results"][0]["status"] == "passed" }.count).must_be :>, 1

      assert_exit_code 100, out
    end
  end

  describe "with a profile containing exceptions outside controls" do
    let(:out) { inspec("exec " + File.join(profile_path, "raise_outside_control") + " --no-create-lockfile") }
    it "gives the failure reason" do
      _(stdout).must_include "Failure Message: Failed to load source for controls/raises.rb: Something unforeseen..."
    end

    it "exits non-zero" do
      assert_exit_code 102, out
    end
  end

  describe "when running both a valid profile and one that fails to load" do
    let(:out) { inspec("exec " + File.join(profile_path, "raise_outside_control") + " " + File.join(profile_path, "basic_profile") + " --no-create-lockfile --no-color") }
    it "gives the failure reason for the failing profile" do
      _(stdout).must_include "Failure Message: Failed to load source for controls/raises.rb: Something unforeseen..."
    end

    it "reports results for the working profile" do
      _(stdout).must_include "Profile Summary: 1 successful control"
    end

    it "exits non-zero" do
      assert_exit_code 102, out
    end
  end

  describe "with a profile containing control overrides" do
    let(:out) { inspec("exec " + File.join(profile_path, "wrapper-override") + " --no-create-lockfile --vendor-cache " + File.join(profile_path, "wrapper-override", "vendor") + " --reporter json") }
    let(:json) { JSON.load(stdout) }
    let(:controls) { json["profiles"][0]["controls"] }
    let(:child_profile) { json["profiles"].select { |p| p["name"] == "myprofile1" }.first }
    let(:child_control) { child_profile["controls"].select { |c| c["title"] == "Profile 1 - Control 2-updated" }.first }
    let(:override) { controls.select { |c| c["title"] == "Profile 1 - Control 2-updated" }.first }

    it "completes the run with parent control overrides" do
      _(stderr).must_be_empty

      if is_windows?
        assert_exit_code 100, out
      else
        assert_exit_code 0, out
      end

      _(controls.count).must_equal 2

      # check for json override
      # TODO: Brittle test expects the leading spaces.
      expected_value = <<-END
  control 'pro1-con2' do
    impact 0.999
    title 'Profile 1 - Control 2-updated'
    desc 'Profile 1 - Control 2 description-updated'
    desc 'overwrite me', 'it is overwritten'
    desc 'new entry', 'this is appended to the description list'
    tag 'password-updated'
    ref 'Section 3.5.2.1', url: 'https://example.com'
    describe file('/etc/passwd') do
      it { should exist }
    end
  end
      END
      _(override["code"]).must_equal expected_value
      _(override["impact"]).must_equal 0.999
      _(override["descriptions"]).must_equal([
        { "label" => "default",
          "data" => "Profile 1 - Control 2 description-updated",
        },
        { "label" => "overwrite me",
          "data" => "it is overwritten",
        },
        { "label" => "new entry",
          "data" => "this is appended to the description list",
        },
      ])
      _(override["title"]).must_equal "Profile 1 - Control 2-updated"
      tags_assert = { "password" => nil, "password-updated" => nil }
      _(override["tags"]).must_equal tags_assert
      _(child_profile["parent_profile"]).must_equal "wrapper-override"

      # check for original code on child profile
      expected_value = <<~END
        control 'pro1-con2' do
          impact 0.9
          title 'Profile 1 - Control 2'
          desc 'Profile 1 - Control 2 description'
          desc 'overwrite me', 'overwrite this'
          tag 'password'
          describe file('/etc/passwdddddddddd') do
            it { should exist }
          end
        end
      END
      _(child_control["code"]).must_equal expected_value

      _(stderr).must_be_empty

      if is_windows?
        assert_exit_code 100, out
      else
        assert_exit_code 0, out
      end
    end
  end

  describe "when using multiple custom resources with each other" do
    let(:out) { inspec("exec " + File.join(examples_path, "custom-resource") + " --no-create-lockfile") }

    it "completes the run with failed controls but no exception" do
      _(stderr).must_be_empty

      assert_exit_code 0, out
    end
  end

  describe "when using a profile with non-UTF characters and wrong encoding" do
    let(:out) { inspec("exec " + File.join(profile_path, "wrong-char-profile") + " --no-create-lockfile") }

    it "completes the run with failed controls but no exception" do
      _(stderr).must_be_empty

      assert_exit_code 0, out
    end
  end

  describe "when targeting private GitHub profiles" do
    let(:private_profile) do
      URI.parse("https://github.com/chef/inspec-test-profile-private.git")
    end

    # This tests requires that a private SSH key be provided for a user that has
    # access to the private profile repo
    if ENV["INSPEC_TEST_SSH_KEY_PATH"]
      it "can use SSH + Git" do
        target = "git@" + private_profile.host + ":" + private_profile.path
        ssh_prefix = 'GIT_SSH_COMMAND="ssh -i ' +
          ENV["INSPEC_TEST_SSH_KEY_PATH"] +
          '"'
        inspec_command = "exec " + target + " --reporter json-min"
        inspec(inspec_command, ssh_prefix)

        _(JSON.parse(stdout)["controls"][0]["status"]).must_equal "passed"

        _(stderr).must_equal ""

        assert_exit_code 0, out
      end
    end

    # This tests requires that a GitHub API token be provided for a user that
    # has access to the private profile repo
    if ENV["INSPEC_TEST_GITHUB_TOKEN"]
      it "can use HTTPS + token + Git" do
        private_profile.userinfo = ENV["INSPEC_TEST_GITHUB_TOKEN"]
        inspec_command = "exec " + private_profile.to_s + " --reporter json-min"
        inspec(inspec_command)

        _(JSON.parse(stdout)["controls"][0]["status"]).must_equal "passed"

        _(stderr).must_equal ""

        assert_exit_code 0, out
      end
    end
  end

  describe "when specifying a config file" do
    let(:run_result) { run_inspec_process("exec " + File.join(profile_path, "simple-metadata") + " " + cli_args, json: true, env: env) }
    let(:seen_target_id) { @json["platform"]["target_id"] }
    let(:stderr) { run_result.stderr }
    let(:env) { {} }

    describe "when using the legacy --json-config option" do
      let(:cli_args) { "--json-config " + File.join(config_dir_path, "json-config", "good.json") }
      it "should see the custom target ID value" do
        _(stderr).must_be_empty # TODO: one day deprecate the --json-config option
        _(seen_target_id).must_equal "from-config-file"
      end
    end

    describe "when using the --config option to read from a custom file" do
      let(:cli_args) { "--config " + File.join(config_dir_path, "json-config", "good.json") }
      it "should see the custom target ID value" do
        _(stderr).must_be_empty
        _(seen_target_id).must_equal "from-config-file"
      end
    end

    unless windows?
      describe "when using the --config option to read from STDIN" do
        let(:json_path) { File.join(config_dir_path, "json-config", "good.json") }
        let(:cli_args) { "--config -" }
        let(:opts) { { prefix: "cat " + json_path + " | ", json: true, env: env } }
        let(:njopts) { opts.merge(json: false) }

        # DO NOT use the `let`-defined run_result through here
        # If you do, it will execute twice, and cause STDIN to read empty on the second time
        it "exec should see the custom target ID value" do
          result = run_inspec_process( "exec " + File.join(profile_path, "simple-metadata") + " " + cli_args + " ", opts )

          _(result.stderr).must_be_empty
          _(@json["platform"]["target_id"]).must_equal "from-config-file"
        end

        it "detect should exit 0" do
          result = run_inspec_process( "detect " + cli_args + " ", njopts )

          _(result.stderr).must_be_empty

          assert_exit_code 0, result
        end

        it "shell should exit 0" do
          result = run_inspec_process( 'shell -c "platform.family" ' + cli_args + " ", njopts )

          _(result.stderr).must_be_empty

          assert_exit_code 0, result
        end
      end
    end

    describe "when reading from the default location" do
      # Should read from File.join(config_dir_path, 'fakehome-2', '.inspec', 'config.json')
      let(:env) { { "HOME" => File.join(config_dir_path, "fakehome-2") } }
      let(:cli_args) { "" }
      it "should see the homedir target ID value" do
        _(stderr).must_be_empty

        _(seen_target_id).must_equal "from-fakehome-config-file"
      end
    end

    describe "when --config points to a nonexistant location" do
      let(:cli_args) { "--config " + "no/such/path" }
      it "should issue an error with the file path" do
        _(stderr).wont_match looks_like_a_stacktrace
        _(stderr).must_include "Could not read configuration file" # Should specify error
        _(stderr).must_include "no/such/path" # Should include error value seen

        assert_exit_code 1, run_result
      end
    end

    describe "when --config points to a malformed file" do
      let(:cli_args) { "--config " + File.join(config_dir_path, "json-config", "malformed.json") }
      it "should issue an error with the parse message" do
        _(stderr).wont_match looks_like_a_stacktrace
        _(stderr).must_include "Failed to load JSON"
        _(stderr).must_include "Config was:"

        assert_exit_code 1, run_result
      end
    end

    describe "when --config points to an invalid file" do
      let(:cli_args) { "--config " + File.join(config_dir_path, "json-config", "invalid.json") }
      it "should issue an error with the parse message" do
        _(stderr).wont_match looks_like_a_stacktrace
        _(stderr).must_include "Unrecognized top-level configuration"
        _(stderr).must_include "this_key_is_invalid"

        assert_exit_code 1, run_result
      end
    end
  end

  describe "when specifying the execution target" do
    let(:local_plat) do
      json = run_inspec_process("detect --format json", {}).stdout
      # .slice is available in ruby 2.5+
      JSON.parse(json).select { |k, v| %w{name release}.include? k }
    end
    let(:run_result) { run_inspec_process("exec " + File.join(profile_path, "simple-metadata") + " " + cli_args, json: true) }
    let(:seen_platform) { run_result; @json["platform"].select { |k, v| %w{name release target_id}.include? k } }
    let(:stderr) { run_result.stderr }

    describe "when neither target nor backend is specified" do
      let(:cli_args) { "" }
      it "should connect to the local platform" do
        _(seen_platform).must_equal local_plat
      end
    end

    describe "when local:// is specified" do
      let(:cli_args) { " -t local:// " }
      it "should connect to the local platform" do
        _(seen_platform).must_equal local_plat
      end
    end

    describe "when an unrecognized backend is specified" do
      let(:cli_args) { "-b garble " }
      it "should exit with an error" do
        _(stderr).wont_match looks_like_a_stacktrace
        # "Can't find train plugin garble. Please install it first"
        _(stderr).must_include "Can't find train plugin"
        _(stderr).must_include "garble"

        assert_exit_code 1, run_result
      end
    end

    describe "when an unrecognized target schema is specified" do
      let(:cli_args) { "-t garble:// " }
      it "should exit with an error" do
        _(stderr).wont_match looks_like_a_stacktrace
        # "Can't find train plugin garble. Please install it first"
        _(stderr).must_include "Can't find train plugin"
        _(stderr).must_include "garble"

        assert_exit_code 1, run_result
      end
    end

    describe "when a schemaless URI is specified" do
      let(:cli_args) { "-t garble " }
      it "should exit with an error" do
        _(stderr).wont_match looks_like_a_stacktrace
        # "Could not recognize a backend from the target garble - use a URI
        # format with the backend name as the URI schema.  Example: 'ssh://somehost.com'
        # or 'transport://credset' or 'transport://' if credentials are provided
        #  outside of InSpec."
        _(stderr).must_include "Could not recognize a backend"
        _(stderr).must_include "garble"
        _(stderr).must_include "ssh://somehost.com"
        _(stderr).must_include "transport://credset"

        assert_exit_code 1, run_result
      end
    end

    describe "when a target URI with a known credset is used" do
      let(:cli_args) { "--target mock://mycredset" + " --config " + File.join(config_dir_path, "json-config", "mock-credset.json") }
      it "should connect to the mock platform" do
        _(seen_platform).must_equal({ "name" => "mock", "release" => "unknown", "target_id" => "from-mock-credset-config-file" })
      end
    end
  end

  describe "when targeting cloud resource packs" do
    let(:cloud_path) { profile_path + "/cloud/" }
    let(:run_result) { run_inspec_process("exec " + cloud_profile + " " + args, env: env) }
    let(:env) { {} }

    describe "when targeting aws" do
      let(:cloud_profile) { cloud_path + "test-aws" }
      # Use log level FATAL to absorb WARNs from deprecataions and ERRORs from not having credentials set.
      # An actual stacktrace then will appear as sole stderr output
      let(:args) { "-t aws://fakecreds --log-level fatal " }
      it "should fail to connect to aws due to lack of creds but not stacktrace" do
        _(run_result.stderr).must_be_empty
      end
    end

    describe "when targeting azure" do
      let(:cloud_profile) { cloud_path + "test-azure" }
      let(:args) { "-t azure://" }
      it "should fail to connect to azure due to lack of creds but not stacktrace" do
        _(run_result.stderr).must_equal "Tenant id cannot be nil\n"
      end
    end

    describe "when targeting gcp" do
      let(:cloud_profile) { cloud_path + "test-gcp" }
      let(:args) { "-t gcp:// --input gcp_project_id=fakeproject" }
      let(:env) { { GOOGLE_AUTH_SUPPRESS_CREDENTIALS_WARNINGS: 1 } }
      it "should fail to connect to gcp due to lack of creds but not stacktrace" do
        _(run_result.stderr).must_include "Could not load the default credentials."
      end
    end

  end

  describe "when evaluating profiles with only_if" do
    let(:run_result) { run_inspec_process("exec #{profile}", json: true) }
    describe "when running a profile with a variety of skips" do
      let(:profile) { "#{profile_path}/only_if/skip-control" }
      it "should correctly skip in individual controls" do
        run_result
        _(@json.dig("profiles", 0, "controls", 0, "results", 0, "status")).must_equal "passed"
        _(@json.dig("profiles", 0, "controls", 1, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 1, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition."
        _(@json.dig("profiles", 0, "controls", 2, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 2, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition: here is a message"
        # 1/0 in test body
        _(@json.dig("profiles", 0, "controls", 3, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 3, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition."
        # 1/0 in resource declaration but it follows the only_if
        _(@json.dig("profiles", 0, "controls", 4, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 4, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition."
        # resource declaration but it precedes the only_if
        _(@json.dig("profiles", 0, "controls", 5, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 5, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition."
        # multiple only_ifs
        _(@json.dig("profiles", 0, "controls", 6, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 6, "results", 0, "skip_message")).must_equal "Skipped control due to only_if condition: here is a different message"
      end
    end
    describe "when running a profile with an only_if at the top-level" do
      let(:profile) { "#{profile_path}/only_if/skip-file" }
      it "should correctly skip entire files" do
        run_result
        # first control is in a separate file
        _(@json.dig("profiles", 0, "controls", 0, "results", 0, "status")).must_equal "passed"
        # Latter three are in the same file
        _(@json.dig("profiles", 0, "controls", 1, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 2, "results", 0, "status")).must_equal "skipped"
        _(@json.dig("profiles", 0, "controls", 3, "results", 0, "status")).must_equal "skipped"
      end
    end
  end

  describe "when running a profile using timeouts on a command resource" do
    let(:profile) { "#{profile_path}/timeouts" }

    describe "when using the DSL command resource option" do
      let(:run_result) { run_inspec_process("exec #{profile}") }

      it "properly timesout an inlined command resource" do
        # Command timeout not available on local windows pipe train transports
        skip if windows?
        _(run_result.stderr).must_be_empty

        # Control with inline timeout should be interrupted correctly
        _(run_result.stdout).must_include "Command `sleep 10; echo oops` timed out after 2 seconds"
        # Subsequent control must still run correctly
        _(run_result.stdout).must_include "Command: `echo hello` exit_status is expected to cmp == 0"
      end
    end

    describe "when using the CLI option to override the command timeout" do
      let(:run_result) { run_inspec_process("exec #{profile} --command-timeout 1") }
      it "properly overrides the DSL setting with the CLI timeout option" do
        # Command timeout not available on local windows pipe train transports
        skip if windows?
        _(run_result.stderr).must_be_empty

        # Command timeout should be interrupted correctly, with CLI timeout applied
        _(run_result.stdout).must_include "Command `sleep 10; echo oops` timed out after 1 seconds"
        # Subsequent control must still run correctly
        _(run_result.stdout).must_include "Command: `echo hello` exit_status is expected to cmp == 0"
      end
    end
  end

  describe "when using the --reporter-include-source option with the CLI reporter" do
    let(:profile) { "#{profile_path}/sorted-results/sort-me-1" } # A profile with controls separated in multiple files
    let(:run_result) { run_inspec_process("exec #{profile} --reporter-include-source") }
    it "includes the control source code" do
      _(run_result.stderr).must_be_empty

      expected = %r{Control Source from .+test/fixtures/profiles/sorted-results/sort-me-1/controls/a-uvw.rb:1..6}
      _(run_result.stdout).must_match expected
      expected = <<EOT
     control "w" do
       describe "anything" do
         it { should eq "anything" }
       end
     end
EOT
      _(run_result.stdout).must_include expected

      expected = %r{Control Source from .+test/fixtures/profiles/sorted-results/sort-me-1/controls/c-rst.rb:1..6}
      _(run_result.stdout).must_match expected
      expected = <<EOT
     control "r" do
       describe "anything" do
         it { should eq "anything" }
       end
     end
EOT
      _(run_result.stdout).must_include expected

    end
  end
end
