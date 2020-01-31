require "helper"
require "train"

ENV["CHEF_LICENSE"] = "accept-no-persist"
ENV["CHEF_TELEMETRY"] = "opt-out-no-persist"

CMD = Train.create("local", command_runner: :generic).connection

class Module
  include Minitest::Spec::DSL
end

module FunctionalHelper
  extend Minitest::Spec::DSL
  extend Minitest::Guard

  let(:repo_path) do
    path = File.expand_path("../../..", __FILE__)
    # fix for vagrant repo pathing
    path.gsub!("//vboxsvr", "C:") if is_windows?
    path
  end
  let(:inspec_path) { File.join(repo_path, "inspec-bin", "bin", "inspec") }
  libdir = File.expand_path "lib"
  let(:exec_inspec) { [Gem.ruby, "-I#{libdir}", inspec_path].join " " }
  let(:mock_path) { File.join(repo_path, "test", "fixtures") }
  let(:profile_path) { File.join(mock_path, "profiles") }
  let(:examples_path) { File.join(profile_path, "old-examples") }
  let(:example_profile) { File.join(examples_path, "profile") }
  let(:meta_profile) { File.join(examples_path, "meta-profile") }
  let(:example_control) { File.join(example_profile, "controls", "example-tmp.rb") }
  let(:inheritance_profile) { File.join(examples_path, "inheritance") }
  let(:failure_control) { File.join(profile_path, "failures", "controls", "failures.rb") }
  let(:simple_inheritance) { File.join(profile_path, "simple-inheritance") }
  let(:sensitive_profile) { File.join(examples_path, "profile-sensitive") }
  let(:config_dir_path) { File.join(mock_path, "config_dirs") }

  let(:dst) do
    # create a temporary path, but we only want an auto-clean helper
    # so remove the file and give back the path
    res = Tempfile.new("inspec-shred")
    res.close
    FileUtils.rm(res.path)
    TMP_CACHE[res.path] = res
  end

  root_dir = windows? ? "C:" : "/etc"
  ROOT_LICENSE_PATH = "#{root_dir}/chef/accepted_licenses/inspec".freeze

  def without_license
    ENV.delete "CHEF_LICENSE"

    FileUtils.rm_f ROOT_LICENSE_PATH

    yield

    FileUtils.rm_f ROOT_LICENSE_PATH
  ensure
    ENV["CHEF_LICENSE"] = "accept-no-persist"
  end

  def assert_exit_code(exp, cmd)
    exp = 1 if windows? && (exp != 0)
    assert_equal exp, cmd.exit_status
  end

  def convert_windows_output(text)
    text = text.force_encoding("UTF-8")
    text.gsub!("[PASS]", "✔")
    text.gsub!("\033[0;1;32m", "\033[38;5;41m")
    text.gsub!("[SKIP]", "↺")
    text.gsub!("\033[0;37m", "\033[38;5;247m")
    text.gsub!("[FAIL]", "×")
    text.gsub!("\033[0;1;31m", "\033[38;5;9m")
  end

  def self.is_windows?
    RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/
  end

  def is_windows?
    FunctionalHelper.is_windows?
  end

  def stderr_ignore_deprecations(result)
    stderr = result.stderr
    suffix = stderr.end_with?("\n") ? "\n" : ""
    stderr.split("\n").reject { |l| l.include? " DEPRECATION: " }.join("\n") + suffix
  end

  def assert_json_controls_passing(_result = nil) # dummy arg
    # Strategy: assemble an array of tests that failed or skipped, and insist it is empty
    # @json['profiles'][0]['controls'][0]['results'][0]['status']
    failed_tests = []
    @json["profiles"].each do |profile_struct|
      profile_name = profile_struct["name"]
      profile_struct["controls"].each do |control_struct|
        control_name = control_struct["id"]
        control_struct["results"].compact.each do |test_struct|
          test_desc = test_struct["code_desc"]
          if test_struct["status"] != "passed"
            failed_tests << "#{profile_name}/#{control_name}/#{test_desc}"
          end
        end
      end
    end

    _(failed_tests).must_be_empty
  end

  @inspec_mutex ||= Mutex.new

  def self.inspec_mutex
    @inspec_mutex
  end

  def self.inspec_cache
    @inspec_cache ||= {}
  end

  def inspec_cache
    FunctionalHelper.inspec_cache
  end

  def inspec_mutex
    FunctionalHelper.inspec_mutex
  end

  def run_cmd(commandline, prefix = nil)
    inspec_mutex.synchronize { # rubocop:disable Style/BlockDelimiters
      inspec_cache[[commandline, prefix]] ||=
        if is_windows?
          invocation = "/windows/system32/cmd /C \"#{prefix} #{commandline}\""
          # puts
          # puts "CMD = #{invocation}"
          result = CMD.run_command(invocation)
          result.stdout.encode!(universal_newline: true)
          result.stderr.encode!(universal_newline: true)
          convert_windows_output(result.stdout)
          # remove the CLIXML header trash in windows
          result.stderr.gsub!("#< CLIXML\n", "")
          result
        else
          invocation = "#{prefix} #{commandline}"
          CMD.run_command(invocation)
        end
    }
  end

  def inspec(commandline, prefix = nil)
    run_cmd "#{exec_inspec} #{commandline}", prefix
  end

  def inspec_with_env(commandline, env = {})
    inspec(commandline, assemble_env_prefix(env))
  end

  # This version allows additional options.
  # @param String command_line Invocation, without the word 'inspec'
  # @param Hash opts Additonal options, see below
  #    :env Hash A hash of environment vars to expose to the invocation.
  #    :prefix String A string to prefix to the invocation. Prefix + env + invocation is the order.
  #    :cwd String A directory to change to. Implemented as 'cd CWD && ' + prefix
  #    :lock Boolean Default false. If false, add `--no-create-lockfile`.
  #    :json Boolean Default false. If true, add `--reporter json` and parse the output, which is stored in @json.
  #    :tmpdir Boolean default true.  If true, wrap execution in a Dir.tmpdir block. Use pre_run and post_run to trigger actions.
  #    :pre_run: Proc(tmp_dir_path) - optional setup block.
  #       tmp_dir will exist and be empty.
  #    :post_run: Proc(FuncTestRunResult, tmp_dir_path) - optional result capture block.
  #       tmp_dir will still exist (for a moment!)
  # @return Train::Extrans::CommandResult
  def run_inspec_process(command_line, opts = {})
    raise "Do not use tmpdir and cwd in the same invocation" if opts[:cwd] && opts[:tmpdir]

    prefix = opts[:cwd] ? "cd " + opts[:cwd] + " && " : ""
    prefix += opts[:prefix] || ""
    prefix += assemble_env_prefix(opts[:env])
    command_line += " --reporter json " if opts[:json] && command_line =~ /\bexec\b/
    command_line += " --no-create-lockfile " if (!opts[:lock]) && command_line =~ /\bexec\b/

    run_result = nil
    if opts[:tmpdir]
      Dir.mktmpdir do |tmp_dir|
        opts[:pre_run].call(tmp_dir) if opts[:pre_run]
        # Do NOT Dir.chdir here - chdir / pwd is per-process, and we are in the
        # test harness process, which will be multithreaded because we parallelize the tests.
        # Instead, make the spawned process change dirs using a cd prefix.
        prefix = "cd " + tmp_dir + " && " + prefix
        run_result = inspec(command_line, prefix)
        opts[:post_run].call(run_result, tmp_dir) if opts[:post_run]
      end
    else
      run_result = inspec(command_line, prefix)
    end

    if opts[:ignore_rspec_deprecations]
      # RSpec keeps issuing a deprecation count to stdout when .should is called explicitly
      # See https://github.com/inspec/inspec/pull/3560
      run_result.stdout.sub!("\n1 deprecation warning total\n", "")
    end

    if opts[:json] && !run_result.stdout.empty?
      begin
        @json = JSON.parse(run_result.stdout)
      rescue JSON::ParserError => e
        warn "JSON PARSE ERROR: %s" % [e.message]
        warn "OUT: <<%s>>"          % [run_result.stdout]
        warn "ERR: <<%s>>"          % [run_result.stderr]
        warn "XIT: %p"              % [run_result.exit_status]
        @json = {}
        @json_error = e
      end
    end

    run_result
  end

  # Copy all examples to a temporary directory for functional tests.
  # You can provide an optional directory which will be handed to your
  # test block with its absolute path. If nothing is provided you will
  # get the path of the examples directory in the tmp environment.
  #
  # @param dir = nil [String] optional directory you want to test
  # @param &block [Type] actual test block
  def prepare_examples(dir = nil, &block)
    Dir.mktmpdir do |tmpdir|
      FileUtils.cp_r(examples_path, tmpdir)
      bn = File.basename(examples_path)
      yield(File.join(tmpdir, bn, dir.to_s))
    end
  end

  private

  def assemble_env_prefix(env = {})
    if is_windows?
      env_prefix = env.to_a.map { |assignment| "set #{assignment[0]}=#{assignment[1]}" }.join("&& ")
      env_prefix += "&& " unless env_prefix.empty?
    else
      env_prefix = env.to_a.map { |assignment| "#{assignment[0]}=#{assignment[1]}" }.join(" ")
      env_prefix += " "
    end
    env_prefix
  end
end

#=========================================================================================#
#                                Plugin Support
#=========================================================================================#
module PluginFunctionalHelper
  include FunctionalHelper

  def run_inspec_with_plugin(command, opts)
    pre = Proc.new do |tmp_dir|
      content = JSON.generate(__make_plugin_file_data_structure_with_path(opts[:plugin_path]))
      File.write(File.join(tmp_dir, "plugins.json"), content)
    end

    opts = {
      pre_run: pre,
      tmpdir: true,
      json: true,
      env: {
        "INSPEC_CONFIG_DIR" => ".", # We're in tmpdir
      },
    }.merge(opts)
    run_inspec_process(command, opts)
  end

  def __make_plugin_file_data_structure_with_path(path)
    # TODO: dry this up, refs #3350
    plugin_name = File.basename(path, ".rb")
    data = __make_empty_plugin_file_data_structure
    data["plugins"] << {
      "name" => plugin_name,
      "installation_type" => "path",
      "installation_path" => path,
    }
    data
  end

  def __make_empty_plugin_file_data_structure
    # TODO: dry this up, refs #3350
    {
      "plugins_config_version" => "1.0.0",
      "plugins" => [],
    }
  end
end
