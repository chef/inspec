# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'functional/helper'

describe 'inspec exec' do
  include FunctionalHelper

  it 'can execute the profile' do
    out = inspec('exec ' + example_profile  + ' --no-create-lockfile')
    out.stderr.must_equal ''
    out.exit_status.must_equal 101
    stdout = out.stdout.force_encoding(Encoding::UTF_8)
    stdout.must_include "\e[38;5;41m  ✔  ssh-1: Allow only SSH Protocol 2\e[0m\n"
    stdout.must_include "\e[38;5;41m  ✔  tmp-1.0: Create /tmp directory\e[0m\n"
    stdout.must_include "
\e[38;5;247m  ↺  gordon-1.0: Verify the version number of Gordon (1 skipped)\e[0m
\e[38;5;247m     ↺  Can't find file `/tmp/gordon/config.yaml`\e[0m
"
    stdout.must_include "\nProfile Summary: \e[38;5;41m2 successful controls\e[0m, 0 control failures, \e[38;5;247m1 control skipped\e[0m\n"
    stdout.must_include "\nTest Summary: \e[38;5;41m4 successful\e[0m, 0 failures, \e[38;5;247m1 skipped\e[0m\n"
  end

  it 'executes a minimum metadata-only profile' do
    out = inspec('exec ' + File.join(profile_path, 'simple-metadata') + ' --no-create-lockfile')
    out.stderr.must_equal ''
    out.exit_status.must_equal 0
    out.stdout.must_equal "
Profile: yumyum profile
Version: (not specified)
Target:  local://

     No tests executed.

Test Summary: 0 successful, 0 failures, 0 skipped
"
  end

  it 'can execute the profile and write to directory' do
    outpath = Dir.tmpdir
    out = inspec("exec #{example_profile} --no-create-lockfile --reporter json:#{outpath}/foo/bar/test.json")
    out.stderr.must_equal ''
    out.exit_status.must_equal 101
    File.exist?("#{outpath}/foo/bar/test.json").must_equal true
    File.stat("#{outpath}/foo/bar/test.json").size.must_be :>, 0
  end

  it 'executes a metadata-only profile' do
    out = inspec('exec ' + File.join(profile_path, 'complete-metadata') + ' --no-create-lockfile')
    out.stderr.must_equal ''
    out.exit_status.must_equal 0
    out.stdout.must_equal "
Profile: title (name)
Version: 1.2.3
Target:  local://

     No tests executed.

Test Summary: 0 successful, 0 failures, 0 skipped
"
  end

  it "executes a profile and reads attributes" do
    out = inspec("exec #{File.join(examples_path, 'profile-attribute')} --no-create-lockfile --attrs #{File.join(examples_path, "profile-attribute.yml")}")
    out.stderr.must_equal ''
    out.exit_status.must_equal 0
    out.stdout.force_encoding(Encoding::UTF_8).must_include "Test Summary: \e[38;5;41m2 successful\e[0m, 0 failures, 0 skipped"
  end

  it 'executes a specs-only profile' do
    out = inspec('exec ' + File.join(profile_path, 'spec_only') + ' --no-create-lockfile')
    out.stderr.must_equal ''
    out.exit_status.must_equal 100
    out.stdout.force_encoding(Encoding::UTF_8).must_include "Target:  local://"
    out.stdout.force_encoding(Encoding::UTF_8).must_include "working"
    out.stdout.force_encoding(Encoding::UTF_8).must_include "✔  should eq \"working\""
    out.stdout.force_encoding(Encoding::UTF_8).must_include "skippy\n"
    out.stdout.force_encoding(Encoding::UTF_8).must_include "↺  This will be skipped intentionally"
    out.stdout.force_encoding(Encoding::UTF_8).must_include "failing"
    out.stdout.force_encoding(Encoding::UTF_8).must_include "×  should eq \"as intended\""
    out.stdout.force_encoding(Encoding::UTF_8).must_include "Test Summary: \e[38;5;41m1 successful\e[0m, \e[38;5;9m1 failure\e[0m, \e[38;5;247m1 skipped\e[0m\n"
  end

  it 'executes only specified controls when selecting passing controls by literal names' do
    out = inspec('exec ' + File.join(profile_path, 'filter_table') + ' --no-create-lockfile --controls 2943_pass_undeclared_field_in_hash 2943_pass_irregular_row_key')
    out.exit_status.must_equal 0
    out.stdout.force_encoding(Encoding::UTF_8).must_include "\nProfile Summary: \e[38;5;41m2 successful controls\e[0m, 0 control failures, 0 controls skipped\n"
  end

  it 'executes only specified controls when selecting failing controls by literal names' do
    out = inspec('exec ' + File.join(profile_path, 'filter_table') + ' --no-create-lockfile --controls 2943_fail_derail_check')
    out.exit_status.must_equal 100
    out.stdout.force_encoding(Encoding::UTF_8).must_include "\nProfile Summary: 0 successful controls, \e[38;5;9m1 control failure\e[0m, 0 controls skipped"
  end

  it 'executes only specified controls when selecting passing controls by regex' do
    out = inspec('exec ' + File.join(profile_path, 'filter_table') + ' --no-create-lockfile --controls \'/^2943_pass/\'')
    out.exit_status.must_equal 0
    out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m4 successful controls\e[0m, 0 control failures, 0 controls skipped"
  end

  it 'executes only specified controls when selecting failing controls by regex' do
    out = inspec('exec ' + File.join(profile_path, 'filter_table') + ' --no-create-lockfile --controls \'/^(2943|2370)_fail/\'')
    out.exit_status.must_equal 100
    out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: 0 successful controls, \e[38;5;9m2 control failures\e[0m, 0 controls skipped"
  end


  it 'can execute a simple file with the default formatter' do
    out = inspec('exec ' + example_control  + ' --no-create-lockfile')
    out.stderr.must_equal ''
    out.exit_status.must_equal 0
    out.stdout.must_include "\nProfile Summary: \e[38;5;41m1 successful control\e[0m, 0 control failures, 0 controls skipped\n"
    out.stdout.must_include "\nTest Summary: \e[38;5;41m2 successful\e[0m, 0 failures, 0 skipped\n"
  end

  describe 'with a profile that is not supported on this OS/platform' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'skippy-profile-os') + ' --no-create-lockfile') }
    let(:json) { JSON.load(out.stdout) }

    it 'exits with an error' do
      out.stderr.must_match(/^This OS\/platform \(.+\) is not supported by this profile.$/)
      out.exit_status.must_equal 1
    end
  end

  describe 'with a profile that contains skipped controls' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'skippy-controls') + ' --no-create-lockfile') }
    let(:json) { JSON.load(out.stdout) }

    it 'exits with an error' do
      out.stdout.force_encoding(Encoding::UTF_8).must_include "skippy\e[0m\n\e[38;5;247m     ↺  This will be skipped super intentionally.\e[0m\n"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "  ↺  CONTROL database: MySQL Session\e[0m\n\e[38;5;247m     ↺  Can't run MySQL SQL checks without authentication\e[0m\n"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: 0 successful controls, 0 control failures, \e[38;5;247m2 controls skipped\e[0m\nTest Summary: 0 successful, 0 failures, \e[38;5;247m2 skipped\e[0m\n"
      out.exit_status.must_equal 101
    end
  end

  describe 'with a profile that contains skipped resources' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'aws-profile')) }
    let(:stdout) { out.stdout.force_encoding(Encoding::UTF_8) }
    it 'exits with an error' do
      stdout.must_include 'Resource Aws_iam_users is not supported on platform'
      stdout.must_include 'Resource Aws_iam_access_keys is not supported on platform'
      stdout.must_include 'Resource Aws_s3_bucket is not supported on platform'
      stdout.must_include '3 skipped'
      out.exit_status.must_equal 101
    end
  end

  describe 'with a profile that is supported on this version of inspec' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'supported_inspec') + ' --no-create-lockfile') }

    it 'exits cleanly' do
      out.stderr.must_equal ''
      out.exit_status.must_equal 0
    end
  end

  describe 'with a profile that is not supported on this version of inspec' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'unsupported_inspec') + ' --no-create-lockfile') }

    it 'does not support this profile' do
      out.exit_status.must_equal 1
      out.stderr.must_equal "This profile requires InSpec version >= 99.0.0. You are running InSpec v#{Inspec::VERSION}.\n"
    end
  end

  describe 'with a profile that loads a library and reference' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'library') + ' --no-create-lockfile') }

    it 'executes the profile without error' do
      out.exit_status.must_equal 0
    end
  end

  describe 'given a profile with controls and anonymous describe blocks' do
    let(:out) { inspec('exec ' + example_control + ' --no-create-lockfile') }

    it 'prints the control results, then the anonymous describe block results' do
      out.stdout.force_encoding(Encoding::UTF_8).must_match(%r{Profile: tests from .*examples.profile.controls.example.rb})
      out.stdout.force_encoding(Encoding::UTF_8).must_include "
Version: (not specified)
Target:  local://

\e[38;5;41m  \xE2\x9C\x94  tmp-1.0: Create /tmp directory\e[0m
\e[38;5;41m     \xE2\x9C\x94  File /tmp should be directory\e[0m

  File /tmp
\e[38;5;41m     \xE2\x9C\x94  should be directory\e[0m

Profile Summary: \e[38;5;41m1 successful control\e[0m, 0 control failures, 0 controls skipped
Test Summary: \e[38;5;41m2 successful\e[0m, 0 failures, 0 skipped\n"
    end
  end

  describe 'given a profile with an anonymous describe block' do
    let(:out) { inspec('exec ' + failure_control + ' --no-create-lockfile') }

    it 'prints the exception message when a test has a syntax error' do
      out.stdout.must_include "undefined method `should_nota' "
    end
  end

  describe 'given an inherited profile that has more that one test per control block' do
    let(:out) { inspec('exec ' + simple_inheritance + ' --no-create-lockfile') }

    it 'should print all the results' do
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  tmp-1.0: Create /tmp directory (1 failed)\e[0m"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  should not be directory\n"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  undefined method `should_nota'"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  should not be directory\n     expected `File /tmp.directory?` to return false, got true\e[0m"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  7 should cmp >= 9\n"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  7 should not cmp == /^\\d$/\n"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "✔  7 should cmp == \"7\""
      out.stdout.force_encoding(Encoding::UTF_8).must_include "  expected: \"01147\"
          got: \"01777\"\n"
    end
  end

  describe 'when passing in two profiles given an inherited profile that has more that one test per control block' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'dependencies', 'profile_d') + ' ' + simple_inheritance + ' --no-create-lockfile') }

    it 'should print all the results' do
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  tmp-1.0: Create /tmp directory (1 failed)\e[0m"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  should not be directory"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  undefined method `should_nota'"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "×  should not be directory\n     expected `File /tmp.directory?` to return false, got true\e[0m"
      out.stdout.force_encoding(Encoding::UTF_8).must_include "✔  profiled-1: Create /tmp directory (profile d)"
    end
  end

  describe 'given an inherited profile' do
    let(:out) { inspec('exec ' + simple_inheritance) }

    it 'should print the profile information and then the test results' do
      out.stdout.force_encoding(Encoding::UTF_8).must_include "\e[38;5;9m  ×  tmp-1.0: Create /tmp directory (1 failed)\e[0m\n\e[38;5;41m     ✔  File /tmp should be directory\e[0m\n\e[38;5;9m     ×  File /tmp should not be directory\n"
    end
  end

  describe 'using namespaced resources' do
    it 'works' do
      out = inspec('exec ' + File.join(profile_path, 'dependencies', 'resource-namespace') + ' --no-create-lockfile')
      out.stderr.must_equal ''
      out.exit_status.must_equal 0
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m1 successful control\e[0m, 0 control failures, 0 controls skipped\n"
    end
  end

  describe 'with require_controls' do
    it 'does not run rules you did not include' do
      out = inspec('exec ' + File.join(profile_path, 'dependencies', 'require_controls_test') + ' --no-create-lockfile')
      out.stderr.must_equal ''
      out.exit_status.must_equal 0
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m1 successful control\e[0m, 0 control failures, 0 controls skipped\n"
    end
  end

  describe "with a 2-level dependency tree" do
    it 'correctly runs tests from the whole tree' do
      out = inspec('exec ' + File.join(profile_path, 'dependencies', 'inheritance') + ' --no-create-lockfile')
      out.stderr.must_equal ''
      out.exit_status.must_equal 0
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m6 successful controls\e[0m, 0 control failures, 0 controls skipped\n"
    end
  end

  describe 'when using profiles on the supermarket' do
    it 'can run supermarket profiles directly from the command line' do
      out = inspec("exec supermarket://nathenharvey/tmp-compliance-profile --no-create-lockfile")
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m2 successful controls\e[0m, 0 control failures, 0 controls skipped\n"
    end

    it 'can run supermarket profiles from inspec.yml' do
      out = inspec("exec #{File.join(profile_path, 'supermarket-dep')} --no-create-lockfile")
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: \e[38;5;41m2 successful controls\e[0m, 0 control failures, 0 controls skipped\n"
    end
  end

  describe 'when a dependency does not support our backend platform' do
    it 'skips the controls from that profile' do
      out = inspec("exec #{File.join(profile_path, 'profile-support-skip')} --no-create-lockfile")
      out.stdout.force_encoding(Encoding::UTF_8).must_include "Profile Summary: 0 successful controls, 0 control failures, \e[38;5;247m2 controls skipped\e[0m\n"
    end
  end

  describe 'when trying to use --sudo with a local target' do
    it 'must print an error and exit' do
      out = inspec("exec #{File.join(profile_path, 'profile-support-skip')} --sudo")
      str = "Sudo is only valid when running against a remote host. To run this locally with elevated privileges, run the command with `sudo ...`.\n"
      out.stderr.force_encoding(Encoding::UTF_8).must_include str
      out.exit_status.must_equal 1
    end
  end

  describe 'when --no-color is used' do
    it 'does not output color control characters' do
      out = inspec('exec ' + File.join(profile_path, 'simple-metadata') + ' --no-color')
      out.exit_status.must_equal 0
      out.stdout.wont_include "\e[38"
    end
  end

  describe 'when --password is used' do
    it 'raises an exception if no password is provided' do
      out = inspec('exec ' + example_profile + ' --password')
      out.exit_status.must_equal 1
      out.stderr.must_include 'Please provide a value for --password. For example: --password=hello.'
    end
  end

  describe 'when --sudo-password is used' do
    it 'raises an exception if no sudo password is provided' do
      out = inspec('exec ' + example_profile + ' --sudo-password')
      out.exit_status.must_equal 1
      out.stderr.must_include 'Please provide a value for --sudo-password. For example: --sudo-password=hello.'
    end
  end

  describe 'with sensitive resources' do
    it 'hides sensitive output' do
      out = inspec('exec ' + sensitive_profile  + ' --no-create-lockfile')
      out.stderr.must_equal ''
      out.exit_status.must_equal 100
      stdout = out.stdout.force_encoding(Encoding::UTF_8)
      stdout.must_include '×  should eq "billy"'
      stdout.must_include 'expected: "billy"'
      stdout.must_include 'got: "bob"'
      stdout.must_include '×  should eq "secret"'
      stdout.must_include '*** sensitive output suppressed ***'
      stdout.must_include "\nTest Summary: \e[38;5;41m2 successful\e[0m, \e[38;5;9m2 failures\e[0m, 0 skipped\n"
    end
  end

  describe 'with a profile containing exceptions in the controls' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'exception-in-control') + ' --no-create-lockfile --reporter json') }
    let(:json) { JSON.load(out.stdout) }
    let(:controls) { json['profiles'][0]['controls'] }

    it 'completes the run with failed controls but no exception' do
      out.stderr.must_be_empty
      out.exit_status.must_equal 100
      controls.count.must_equal 10
      controls.select { |c| c['results'][0]['status'] == 'failed' }.count.must_be :>, 1
      controls.select { |c| c['results'][0]['status'] == 'passed' }.count.must_be :>, 1
    end
  end

  describe 'with a profile containing control overrides' do
    let(:out) { inspec('exec ' + File.join(profile_path, 'wrapper-override') + ' --no-create-lockfile --vendor-cache ' +  File.join(profile_path, 'wrapper-override', 'vendor') + ' --reporter json') }
    let(:json) { JSON.load(out.stdout) }
    let(:controls) { json['profiles'][0]['controls'] }
    let(:child_profile) { json['profiles'].select { |p| p['name'] == 'myprofile1' }.first }
    let(:override) { controls.select { |c| c['title'] == 'Profile 1 - Control 2-updated' }.first }

    it 'completes the run with failed controls but no exception' do
      out.stderr.must_be_empty
      out.exit_status.must_equal 0
      controls.count.must_equal 2

      # check for json override
      assert = "  control 'pro1-con2' do\n    impact 0.999\n    title 'Profile 1 - Control 2-updated'\n    desc 'Profile 1 - Control 2 description-updated'\n    tag 'password-updated'\n    ref 'Section 3.5.2.1', url: 'https://example.com'\n    describe file('/etc/passwd') do\n      it { should exist }\n    end\n  end\n"
      override['code'].must_equal assert
      override['impact'].must_equal 0.999
      override['title'].must_equal "Profile 1 - Control 2-updated"
      tags_assert = {"password"=>nil, "password-updated"=>nil}
      override['tags'].must_equal tags_assert
      child_profile['parent_profile'].must_equal 'wrapper-override'
    end
  end

  describe 'when using multiple custom resources with each other' do
    let(:out) { inspec('exec ' + File.join(examples_path, 'custom-resource') + ' --no-create-lockfile') }

    it 'completes the run with failed controls but no exception' do
      out.stderr.must_be_empty
      out.exit_status.must_equal 0
    end
  end
end
