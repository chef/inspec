# copyright: 2015, Dominik Richter

require "forwardable" unless defined?(Forwardable)
require "uri" unless defined?(URI)
require "inspec/backend"
require "inspec/profile_context"
require "inspec/profile"
require "inspec/metadata"
require "inspec/config"
require "inspec/dependencies/cache"
require "inspec/dist"
require "inspec/reporters"
require "inspec/runner_rspec"
# spec requirements

module Inspec
  #
  # Inspec::Runner coordinates the running of tests and is the main
  # entry point to the application.
  #
  # Users are expected to insantiate a runner, add targets to be run,
  # and then call the run method:
  #
  # ```
  # r = Inspec::Runner.new()
  # r.add_target("/path/to/some/profile")
  # r.add_target("http://url/to/some/profile")
  # r.run
  # ```
  #
  class Runner
    extend Forwardable

    attr_reader :backend, :rules
    attr_accessor :target_profiles

    attr_accessor :test_collector

    def attributes
      Inspec.deprecate(:rename_attributes_to_inputs, "Don't call runner.attributes, call runner.inputs")
      inputs
    end

    def initialize(conf = {})
      @rules = []
      # If we were handed a Hash config (by audit cookbook or kitchen-inspec),
      # upgrade it to a proper config. This handles a lot of config finalization,
      # like reporter parsing.
      @conf = conf.is_a?(Hash) ? Inspec::Config.new(conf) : conf
      @conf[:logger] ||= Logger.new(nil)
      @target_profiles = []
      @controls = @conf[:controls] || []
      @tags = @conf[:tags] || []
      @depends = @conf[:depends] || []
      @create_lockfile = @conf[:create_lockfile]
      @cache = Inspec::Cache.new(@conf[:vendor_cache])

      @test_collector = @conf.delete(:test_collector) || begin
        RunnerRspec.new(@conf)
      end

      if @conf[:waiver_file]
        waivers = @conf.delete(:waiver_file)
        @conf[:input_file] ||= []
        @conf[:input_file].concat waivers
      end

      # About reading inputs:
      #   @conf gets passed around a lot, eventually to
      # Inspec::InputRegistry.register_external_inputs.
      #
      #   @conf may contain the key :attributes or :inputs, which is to be a Hash
      # of values passed in from the Runner API.
      # This is how kitchen-inspec and the audit_cookbook pass in inputs.
      #
      #   @conf may contain the key :attrs or :input_file, which is to be an Array
      # of file paths, each a YAML file. This how --input-file works.

      configure_transport
    end

    def tests
      @test_collector.tests
    end

    def configure_transport
      @backend = Inspec::Backend.create(@conf)
      @test_collector.backend = @backend
    end

    def reset
      @test_collector.reset
      @target_profiles.each do |profile|
        profile.runner_context.rules = {}
      end
      @rules = []
    end

    def load
      all_controls = []

      @target_profiles.each do |profile|
        @test_collector.add_profile(profile)
        next unless profile.supports_platform?

        write_lockfile(profile) if @create_lockfile
        profile.locked_dependencies
        profile_context = profile.load_libraries

        profile_context.dependencies.list.values.each do |requirement|
          unless requirement.profile.supports_platform?
            Inspec::Log.warn "Skipping profile: '#{requirement.profile.name}'" \
             " on unsupported platform: '#{@backend.platform.name}/#{@backend.platform.release}'."
            next
          end
          @test_collector.add_profile(requirement.profile)
        end

        begin
          tests = profile.collect_tests
          all_controls += tests unless tests.nil?
        rescue Inspec::Exceptions::ProfileLoadFailed => e
          Inspec::Log.error "Failed to load profile #{profile.name}: #{e}"
          profile.set_status_message e.to_s
          next
        end
      end

      all_controls.each do |rule|
        register_rule(rule) unless rule.nil?
      end
    end

    def run(with = nil)
      Inspec::Log.debug "Starting run with targets: #{@target_profiles.map(&:to_s)}"
      load
      run_tests(with)
    end

    def render_output(run_data)
      return if @conf["reporter"].nil?

      @conf["reporter"].each do |reporter|
        result = Inspec::Reporters.render(reporter, run_data)
        raise Inspec::ReporterError, "Error generating reporter '#{reporter[0]}'" if result == false
      end
    end

    def report
      Inspec::Reporters.report(@conf["reporter"].first, @run_data)
    end

    def write_lockfile(profile)
      return false unless profile.writable?

      if profile.lockfile_exists?
        Inspec::Log.debug "Using existing lockfile #{profile.lockfile_path}"
      else
        Inspec::Log.debug "Creating lockfile: #{profile.lockfile_path}"
        lockfile = profile.generate_lockfile
        File.write(profile.lockfile_path, lockfile.to_yaml)
      end
    end

    def run_tests(with = nil)
      @run_data = @test_collector.run(with)
      # dont output anything if we want a report
      render_output(@run_data) unless @conf["report"]
      @test_collector.exit_code
    end

    #
    # add_target allows the user to add a target whose tests will be
    # run when the user calls the run method.
    #
    # A target is a path or URL that points to a profile. Using this
    # target we generate a Profile and a ProfileContext. The content
    # (libraries, tests, and inputs) from the Profile are loaded
    # into the ProfileContext.
    #
    # If the profile depends on other profiles, those profiles will be
    # loaded on-demand when include_content or required_content are
    # called using similar code in Inspec::DSL.
    #
    # Once the we've loaded all of the tests files in the profile, we
    # query the profile for the full list of rules. Those rules are
    # registered with the @test_collector which is ultimately
    # responsible for actually running the tests.
    #
    # TODO: Deduplicate/clarify the loading code that exists in here,
    # the ProfileContext, the Profile, and Inspec::DSL
    #
    # @params target [String] A path or URL to a profile or raw test.
    # @params _opts [Hash] Unused, but still here to avoid breaking kitchen-inspec
    #
    # @eturns [Inspec::ProfileContext]
    #
    def add_target(target, _opts = [])
      profile = Inspec::Profile.for_target(target,
                                           vendor_cache: @cache,
                                           backend: @backend,
                                           controls: @controls,
                                           tags: @tags,
                                           runner_conf: @conf)
      raise "Could not resolve #{target} to valid input." if profile.nil?

      @target_profiles << profile if supports_profile?(profile)
    end

    def supports_profile?(profile)
      unless profile.supports_runtime?
        raise "This profile requires #{Inspec::Dist::PRODUCT_NAME} version "\
             "#{profile.metadata.inspec_requirement}. You are running "\
             "#{Inspec::Dist::PRODUCT_NAME} v#{Inspec::VERSION}.\n"
      end

      true
    end

    # In some places we read the rules off of the runner, in other
    # places we read it off of the profile context. To keep the API's
    # the same, we provide an #all_rules method here as well.
    def all_rules
      @rules
    end

    def register_rules(ctx)
      new_tests = false
      ctx.rules.each do |rule_id, rule|
        next if block_given? && !(yield rule_id, rule)

        new_tests = true
        register_rule(rule)
      end
      new_tests
    end

    def eval_with_virtual_profile(command)
      require "inspec/fetcher/mock"
      add_target({ "inspec.yml" => "name: inspec-shell" })
      our_profile = @target_profiles.first
      ctx = our_profile.runner_context

      # Load local profile dependencies. This is used in inspec shell
      # to provide access to local profiles that add resources.
      @depends.each do |dep|
        # support for windows paths
        dep = dep.tr("\\", "/")
        Inspec::Profile.for_path(dep, { profile_context: ctx }).load_libraries
      end

      ctx.load(command)
    end

    private

    def block_source_info(block)
      return {} if block.nil? || !block.respond_to?(:source_location)

      opts = {}
      file_path, line = block.source_location
      opts["file_path"] = file_path
      opts["line_number"] = line
      opts
    end

    def get_check_example(method_name, arg, block)
      opts = block_source_info(block)

      return nil if arg.empty?

      resource = arg[0]
      # check to see if we are using a filtertable object
      resource = resource.resource if resource.is_a? FilterTable::Table
      if resource.respond_to?(:resource_skipped?) && resource.resource_skipped?
        return rspec_skipped_block(arg, opts, resource.resource_exception_message)
      end

      if resource.respond_to?(:resource_failed?) && resource.resource_failed?
        return rspec_failed_block(arg, opts, resource.resource_exception_message)
      end

      # If neither skipped nor failed then add the resource
      add_resource(method_name, arg, opts, block)
    end

    def register_rule(rule)
      Inspec::Log.debug "Registering rule #{rule}"
      @rules << rule
      checks = ::Inspec::Rule.prepare_checks(rule)
      examples = checks.flat_map do |m, a, b|
        get_check_example(m, a, b)
      end.compact

      examples.each { |e| @test_collector.add_test(e, rule) }
    end

    def rspec_skipped_block(arg, opts, message)
      @test_collector.example_group(*arg, opts) do
        # Send custom `it` block to RSpec
        it message
      end
    end

    def rspec_failed_block(arg, opts, message)
      @test_collector.example_group(*arg, opts) do
        # Send custom `it` block to RSpec
        it "" do
          # Raising here to fail the test and get proper formatting
          raise Inspec::Exceptions::ResourceFailed, message
        end
      end
    end

    def add_resource(method_name, arg, opts, block)
      case method_name
      when "describe"
        opts = { backend: @test_collector.backend }.merge opts

        @test_collector.example_group(*arg, opts, &block)
      when "expect"
        block.example_group
      when "describe.one"
        tests = arg.map do |x|
          @test_collector.example_group(x[1][0], block_source_info(x[2]), &x[2])
        end
        return nil if tests.empty?

        successful_tests = tests.find_all(&:run)

        # Return all tests if none succeeds; we will just report full failure
        return tests if successful_tests.empty?

        successful_tests
      else
        raise "A rule was registered with #{method_name.inspect}," \
              "which isn't understood and cannot be processed."
      end
    end
  end
end
