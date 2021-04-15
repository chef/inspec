# Copyright 2015 Dominik Richter

require "forwardable" unless defined?(Forwardable)
require "openssl" unless defined?(OpenSSL)
require "pathname" unless defined?(Pathname)
require "inspec/input_registry"
require "inspec/cached_fetcher" # TODO: split or rename
require "inspec/source_reader"
require "inspec/profile_context"
require "inspec/runtime_profile"
require "inspec/method_source"
require "inspec/dependencies/cache"
require "inspec/dependencies/lockfile"
require "inspec/dependencies/dependency_set"
require "inspec/utils/json_profile_summary"

module Inspec
  class Profile
    extend Forwardable

    def self.resolve_target(target, cache)
      Inspec::Log.debug "Resolve #{target} into cache #{cache.path}"
      Inspec::CachedFetcher.new(target, cache)
    end

    # Check if the profile contains a vendored cache, move content into global cache
    # TODO: use relative file provider
    # TODO: use source reader for Cache as well
    def self.copy_deps_into_cache(file_provider, opts)
      # filter content
      cache = file_provider.files.find_all do |entry|
        entry.start_with?("vendor")
      end
      content = Hash[cache.map { |x| [x, file_provider.binread(x)] }]
      keys = content.keys
      keys.each do |key|
        next if content[key].nil?

        # remove prefix
        rel = Pathname.new(key).relative_path_from(Pathname.new("vendor")).to_s
        tar = Pathname.new(opts[:vendor_cache].path).join(rel)

        FileUtils.mkdir_p tar.dirname.to_s
        Inspec::Log.debug "Copy #{tar} to cache directory"
        File.binwrite(tar.to_s, content[key])
      end
    end

    def self.for_path(path, opts)
      file_provider = FileProvider.for_path(path)
      rp = file_provider.relative_provider

      # copy embedded dependencies into global cache
      copy_deps_into_cache(rp, opts) unless opts[:vendor_cache].nil?

      reader = Inspec::SourceReader.resolve(rp)
      if reader.nil?
        raise("Don't understand inspec profile in #{path}, it " \
             "doesn't look like a supported profile structure.")
      end
      new(reader, opts)
    end

    def self.for_fetcher(fetcher, config)
      opts = config.respond_to?(:final_options) ? config.final_options : config
      opts[:vendor_cache] = opts[:vendor_cache] || Cache.new
      path, writable = fetcher.fetch
      for_path(path, opts.merge(target: fetcher.target, writable: writable))
    end

    def self.for_target(target, opts = {})
      opts[:vendor_cache] ||= Cache.new
      fetcher = resolve_target(target, opts[:vendor_cache])
      for_fetcher(fetcher, opts)
    end

    attr_reader :source_reader, :backend, :runner_context, :check_mode
    attr_accessor :parent_profile, :profile_id, :profile_name
    def_delegator :@source_reader, :tests
    def_delegator :@source_reader, :libraries
    def_delegator :@source_reader, :metadata

    # rubocop:disable Metrics/AbcSize
    def initialize(source_reader, options = {})
      @source_reader = source_reader
      @target = options[:target]
      @logger = options[:logger] || Logger.new(nil)
      @locked_dependencies = options[:dependencies]
      @controls = options[:controls] || []
      @writable = options[:writable] || false
      @profile_id = options[:id]
      @profile_name = options[:profile_name]
      @cache = options[:vendor_cache] || Cache.new
      @input_values = options[:inputs]
      @tests_collected = false
      @libraries_loaded = false
      @state = :loaded
      @check_mode = options[:check_mode] || false
      @parent_profile = options[:parent_profile]
      @legacy_profile_path = options[:profiles_path] || false
      Metadata.finalize(@source_reader.metadata, @profile_id, options)

      # if a backend has already been created, clone it so each profile has its own unique backend object
      # otherwise, create a new backend object
      #
      # This is necessary since we store the RuntimeProfile on the backend object. If a user runs `inspec exec`
      # with multiple profiles, only the RuntimeProfile for the last-loaded profile will be available if
      # we share the backend between profiles.
      #
      # This will cause issues if a profile attempts to load a file via `inspec.profile.file`
      train_options = options.reject { |k, _| k == "target" } # See https://github.com/chef/inspec/pull/1646
      @backend = options[:backend].nil? ? Inspec::Backend.create(Inspec::Config.new(train_options)) : options[:backend].dup
      @runtime_profile = RuntimeProfile.new(self)
      @backend.profile = @runtime_profile

      # The AttributeRegistry is in charge of keeping track of inputs;
      # it is the single source of truth. Now that we have a profile object,
      # we can create any inputs that were provided by various mechanisms.
      options[:runner_conf] ||= Inspec::Config.cached

      # Catch legacy CLI input option usage
      if options[:runner_conf].key?(:attrs)
        Inspec.deprecate(:rename_attributes_to_inputs, "Use --input-file on the command line instead of --attrs.")
        options[:runner_conf][:input_file] = options[:runner_conf].delete(:attrs)
      elsif options[:runner_conf].key?(:input_files)
        # The kitchen-inspec docs say to use plural. Our CLI and internal expectations are singular.
        options[:runner_conf][:input_file] = options[:runner_conf].delete(:input_files)
      end

      # Catch legacy kitchen-inspec input usage
      if options[:runner_conf].key?(:attributes)
        Inspec.deprecate(:rename_attributes_to_inputs, "Use :inputs in your kitchen.yml verifier config instead of :attributes.")
        options[:runner_conf][:inputs] = options[:runner_conf].delete(:attributes)
      end

      Inspec::InputRegistry.bind_profile_inputs(
        # Every input only exists in the context of a profile
        metadata.params[:name], # TODO: test this with profile aliasing
        # Remaining args are possible sources of inputs
        cli_input_files: options[:runner_conf][:input_file], # From CLI --input-file
        profile_metadata: metadata,
        runner_api: options[:runner_conf][:inputs], # This is the route the audit_cookbook and kitchen-inspec take
        cli_input_arg: options[:runner_conf][:input] # The --input name=value CLI option
      )

      @runner_context =
        options[:profile_context] ||
        Inspec::ProfileContext.for_profile(self, @backend)

      if metadata.supports_platform?(@backend)
        @supports_platform = true
      else
        @supports_platform = false
        @state = :skipped
      end
      @supports_runtime = metadata.supports_runtime?
    end

    def name
      metadata.params[:name]
    end

    def version
      metadata.params[:version]
    end

    def writable?
      @writable
    end

    def failed?
      @state == :failed
    end

    #
    # Is this profile is supported on the current platform of the
    # backend machine and the current inspec version.
    #
    # @returns [TrueClass, FalseClass]
    #
    def supported?
      supports_platform? && supports_runtime?
    end

    # We need to check if we're using a Mock'd backend for tests to function.
    # @returns [TrueClass, FalseClass]
    def supports_platform?
      if @supports_platform.nil?
        @supports_platform = metadata.supports_platform?(@backend)
      end
      if @backend.backend.class.to_s == "Train::Transports::Mock::Connection"
        @supports_platform = true
      end

      @supports_platform
    end

    def supports_runtime?
      if @supports_runtime.nil?
        @supports_runtime = metadata.supports_runtime?
      end
      @supports_runtime
    end

    def params
      @params ||= load_params
    end

    def collect_tests(include_list = @controls)
      unless @tests_collected || failed?
        return unless supports_platform?

        locked_dependencies.each(&:collect_tests)

        tests = filter_waived_controls

        # Collect tests
        tests.each do |path, content|
          next if content.nil? || content.empty?

          abs_path = source_reader.target.abs_path(path)
          begin
            @runner_context.load_control_file(content, abs_path, nil)
          rescue => e
            @state = :failed
            raise Inspec::Exceptions::ProfileLoadFailed, "Failed to load source for #{path}: #{e}"
          end
        end
        @tests_collected = true
      end
      @runner_context.all_rules
    end

    # Wipe out waived controls
    def filter_waived_controls
      cfg = Inspec::Config.cached
      return tests unless cfg["filter_waived_controls"]

      ## Find the waivers file
      # - TODO: cli_opts and instance_variable_get could be exposed
      waiver_paths = cfg.instance_variable_get(:@cli_opts)["waiver_file"]
      if waiver_paths.blank?
        Inspec::Log.error "Must use --waiver-file with --filter-waived-controls"
        Inspec::UI.new.exit(:usage_error)
      end

      # # Pull together waiver
      waived_control_ids = []
      waiver_paths.each do |waiver_path|
        waiver_content = YAML.load_file(waiver_path)
        unless waiver_content
          # Note that we will have already issued a detailed warning
          Inspec::Log.error "YAML parsing error in #{waiver_path}"
          Inspec::UI.new.exit(:usage_error)
        end
        waived_control_ids << waiver_content.keys
      end
      waived_control_id_regex = "(#{waived_control_ids.join("|")})"

      ## Purge tests (this could be doone in next block for performance)
      ## TODO: implement earlier with pure AST and pure autocorrect AST
      filtered_tests = {}
      if cfg["retain_waiver_data"]
        # VERY EXPERIMENTAL, but an empty describe block at the top level
        # of the control blocks evaluation of ruby code until later-term
        # waivers (behind the scenes this tells RSpec to hold on and use its internals to lazy load the code). This allows current waiver-data (e.g. skips) to still
        # be processed and rendered
        tests.each do |control_filename, source_code|
          cleared_tests = source_code.scan(/control\s+['"].+?['"].+?(?=(?:control\s+['"].+?['"])|\z)/m).collect do |element|
            next if element.blank?

            if element&.match?(waived_control_id_regex)
              splitlines = element.split("\n")
              splitlines[0] + "\ndescribe '---' do\n" + splitlines[1..-1].join("\n") + "\nend\n"
            else
              element
            end
          end.join("")
          filtered_tests[control_filename] = cleared_tests
        end
      else
        tests.each do |control_filename, source_code|
          cleared_tests = source_code.scan(/control\s+['"].+?['"].+?(?=(?:control\s+['"].+?['"])|\z)/m).select do |control_code|
            !control_code.match?(waived_control_id_regex)
          end.join("")

          filtered_tests[control_filename] = cleared_tests
        end
      end
      filtered_tests
    end

    # This creates the list of controls provided in the --controls options which need to be include
    # for evaluation.
    def include_controls_list
      return [] if @controls.nil? || @controls.empty?

      included_controls = @controls
      # Check for anything that might be a regex in the list, and make it official
      included_controls.each_with_index do |inclusion, index|
        next if inclusion.is_a?(Regexp)
        # Insist the user wrap the regex in slashes to demarcate it as a regex
        next unless inclusion.start_with?("/") && inclusion.end_with?("/")

        inclusion = inclusion[1..-2] # Trim slashes
        begin
          re = Regexp.new(inclusion)
          included_controls[index] = re
        rescue RegexpError => e
          warn "Ignoring unparseable regex '/#{inclusion}/' in --control CLI option: #{e.message}"
          included_controls[index] = nil
        end
      end
      included_controls.compact!
      included_controls
    end

    def load_libraries
      return @runner_context if @libraries_loaded

      locked_dependencies.dep_list.each_with_index do |(_name, dep), i|
        d = dep.profile
        # this will force a dependent profile load so we are only going to add
        # this metadata if the parent profile is supported.
        if @supports_platform && !d.supports_platform?
          # since ruby 1.9 hashes are ordered so we can just use index values here
          # TODO: NO! this is a violation of encapsulation to an extreme
          metadata.dependencies[i][:status] = "skipped"
          msg = "Skipping profile: '#{d.name}' on unsupported platform: '#{d.backend.platform.name}/#{d.backend.platform.release}'."
          metadata.dependencies[i][:status_message] = msg
          metadata.dependencies[i][:skip_message] = msg # Repeat as skip_message for backward compatibility
          next
        elsif metadata.dependencies[i]
          # Currently wrapper profiles will load all dependencies, and then we
          # load them again when we dive down. This needs to be re-done.
          metadata.dependencies[i][:status] = "loaded"
        end

        # rubocop:disable Layout/ExtraSpacing
        c = d.load_libraries                           # !!!RECURSE!!!
        @runner_context.add_resources(c)
      end

      # TODO: why?!? we own both sides of this code
      libs = libraries.map(&:reverse)

      @runner_context.load_libraries(libs)
      @libraries_loaded = true
      @runner_context
    end

    def to_s
      "Inspec::Profile<#{name}>"
    end

    # return info using uncached params
    def info!
      info(load_params.dup)
    end

    def info(res = params.dup) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      # add information about the controls
      res[:controls] = res[:controls].map do |id, rule|
        next if id.to_s.empty?

        data = rule.dup
        data.delete(:checks)
        data[:impact] ||= 0.5
        data[:impact] = 1.0 if data[:impact] > 1.0
        data[:impact] = 0.0 if data[:impact] < 0.0
        data[:id] = id

        # if the code field is empty try and pull info from dependencies
        if data[:code].empty? && parent_profile.nil?
          locked_dependencies.dep_list.each do |_name, dep|
            profile = dep.profile
            code = Inspec::MethodSource.code_at(data[:source_location], profile.source_reader)
            data[:code] = code unless code.nil? || code.empty?
            break unless data[:code].empty?
          end
        end
        data
      end.compact

      # resolve hash structure in groups
      res[:groups] = res[:groups].map do |id, group|
        group[:id] = id
        group
      end

      # add information about the required inputs
      if params[:inputs].nil? || params[:inputs].empty?
        # convert to array for backwards compatability
        res[:inputs] = []
      else
        res[:inputs] = params[:inputs].values.map(&:to_hash)
      end
      res[:sha256] = sha256
      res[:parent_profile] = parent_profile unless parent_profile.nil?

      if @supports_platform
        res[:status_message] = @status_message || ""
        res[:status] = failed? ? "failed" : "loaded"
      else
        res[:status] = "skipped"
        msg = "Skipping profile: '#{name}' on unsupported platform: '#{backend.platform.name}/#{backend.platform.release}'."
        res[:status_message] = msg
      end

      # convert legacy os-* supports to their platform counterpart
      if res[:supports] && !res[:supports].empty?
        res[:supports].each do |support|
          # TODO: deprecate
          support[:"platform-family"] = support.delete(:"os-family") if support.key?(:"os-family")
          support[:"platform-name"] = support.delete(:"os-name") if support.key?(:"os-name")
        end
      end

      res
    end

    # Check if the profile is internally well-structured. The logger will be
    # used to print information on errors and warnings which are found.
    #
    # @return [Boolean] true if no errors were found, false otherwise
    def check # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      # initial values for response object
      result = {
        summary: {
          valid: false,
          timestamp: Time.now.iso8601,
          location: @target,
          profile: nil,
          controls: 0,
        },
        errors: [],
        warnings: [],
      }

      entry = lambda { |file, line, column, control, msg|
        {
          file: file,
          line: line,
          column: column,
          control_id: control,
          msg: msg,
        }
      }

      warn = lambda { |file, line, column, control, msg|
        @logger.warn(msg)
        result[:warnings].push(entry.call(file, line, column, control, msg))
      }

      error = lambda { |file, line, column, control, msg|
        @logger.error(msg)
        result[:errors].push(entry.call(file, line, column, control, msg))
      }

      @logger.info "Checking profile in #{@target}"
      meta_path = @source_reader.target.abs_path(@source_reader.metadata.ref)

      # verify metadata
      m_errors, m_warnings = metadata.valid
      m_errors.each { |msg| error.call(meta_path, 0, 0, nil, msg) }
      m_warnings.each { |msg| warn.call(meta_path, 0, 0, nil, msg) }
      m_unsupported = metadata.unsupported
      m_unsupported.each { |u| warn.call(meta_path, 0, 0, nil, "doesn't support: #{u}") }
      @logger.info "Metadata OK." if m_errors.empty? && m_unsupported.empty?

      # only run the vendor check if the legacy profile-path is not used as argument
      if @legacy_profile_path == false
        # verify that a lockfile is present if we have dependencies
        unless metadata.dependencies.empty?
          error.call(meta_path, 0, 0, nil, "Your profile needs to be vendored with `inspec vendor`.") unless lockfile_exists?
        end

        if lockfile_exists?
          # verify if metadata and lockfile are out of sync
          if lockfile.deps.size != metadata.dependencies.size
            error.call(meta_path, 0, 0, nil, "inspec.yml and inspec.lock are out-of-sync. Please re-vendor with `inspec vendor`.")
          end

          # verify if metadata and lockfile have the same dependency names
          metadata.dependencies.each do |dep|
            # Skip if the dependency does not specify a name
            next if dep[:name].nil?

            # TODO: should we also verify that the soure is the same?
            unless lockfile.deps.map { |x| x[:name] }.include? dep[:name]
              error.call(meta_path, 0, 0, nil, "Cannot find #{dep[:name]} in lockfile. Please re-vendor with `inspec vendor`.")
            end
          end
        end
      end

      # extract profile name
      result[:summary][:profile] = metadata.params[:name]

      count = controls_count
      result[:summary][:controls] = count
      if count == 0
        warn.call(nil, nil, nil, nil, "No controls or tests were defined.")
      else
        @logger.info("Found #{count} controls.")
      end

      # iterate over hash of groups
      params[:controls].each do |id, control|
        sfile = control[:source_location][:ref]
        sline = control[:source_location][:line]
        error.call(sfile, sline, nil, id, "Avoid controls with empty IDs") if id.nil? || id.empty?
        next if id.start_with? "(generated "

        warn.call(sfile, sline, nil, id, "Control #{id} has no title") if control[:title].to_s.empty?
        warn.call(sfile, sline, nil, id, "Control #{id} has no descriptions") if control[:descriptions][:default].to_s.empty?
        warn.call(sfile, sline, nil, id, "Control #{id} has impact > 1.0") if control[:impact].to_f > 1.0
        warn.call(sfile, sline, nil, id, "Control #{id} has impact < 0.0") if control[:impact].to_f < 0.0
        warn.call(sfile, sline, nil, id, "Control #{id} has no tests defined") if control[:checks].nil? || control[:checks].empty?
      end

      # profile is valid if we could not find any error
      result[:summary][:valid] = result[:errors].empty?

      @logger.info "Control definitions OK." if result[:warnings].empty?
      result
    end

    def controls_count
      params[:controls].values.length
    end

    def set_status_message(msg)
      @status_message = msg.to_s
    end

    # generates a archive of a folder profile
    # assumes that the profile was checked before
    def archive(opts)
      # check if file exists otherwise overwrite the archive
      dst = archive_name(opts)
      if dst.exist? && !opts[:overwrite]
        @logger.info "Archive #{dst} exists already. Use --overwrite."
        return false
      end

      # remove existing archive
      FileUtils.rm_f(dst) if dst.exist?
      @logger.info "Generate archive #{dst}."

      # filter files that should not be part of the profile
      # TODO ignore all .files, but add the files to debug output

      # Generate temporary inspec.json for archive
      Inspec::Utils::JsonProfileSummary.produce_json(
        info: info,
        write_path: "#{root_path}inspec.json",
        suppress_output: true
      )

      # display all files that will be part of the archive
      @logger.debug "Add the following files to archive:"
      files.each { |f| @logger.debug "    " + f }
      @logger.debug "    inspec.json"

      if opts[:zip]
        # generate zip archive
        require "inspec/archive/zip"
        zag = Inspec::Archive::ZipArchiveGenerator.new
        zag.archive(root_path, files.push("inspec.json"), dst)
      else
        # generate tar archive
        require "inspec/archive/tar"
        tag = Inspec::Archive::TarArchiveGenerator.new
        tag.archive(root_path, files.push("inspec.json"), dst)
      end

      # Cleanup
      FileUtils.rm_f("#{root_path}inspec.json")

      @logger.info "Finished archive generation."
      true
    end

    def locked_dependencies
      @locked_dependencies ||= load_dependencies
    end

    def lockfile_exists?
      @source_reader.target.files.include?("inspec.lock")
    end

    def lockfile_path
      File.join(cwd, "inspec.lock")
    end

    def root_path
      @source_reader.target.prefix
    end

    def files
      @source_reader.target.files
    end

    #
    # TODO(ssd): Relative path handling really needs to be carefully
    # thought through, especially with respect to relative paths in
    # tarballs.
    #
    def cwd
      @target.is_a?(String) && File.directory?(@target) ? @target : "./"
    end

    def lockfile
      @lockfile ||= if lockfile_exists?
                      Inspec::Lockfile.from_content(@source_reader.target.read("inspec.lock"))
                    else
                      generate_lockfile
                    end
    end

    #
    # Generate an in-memory lockfile. This won't render the lock file
    # to disk, it must be explicitly written to disk by the caller.
    #
    # @param vendor_path [String] Path to the on-disk vendor dir
    # @return [Inspec::Lockfile]
    #
    def generate_lockfile
      res = Inspec::DependencySet.new(cwd, @cache, nil, @backend)
      res.vendor(metadata.dependencies)
      Inspec::Lockfile.from_dependency_set(res)
    end

    def load_dependencies
      config = {
        cwd: cwd,
        cache: @cache,
        backend: @backend,
        parent_profile: name,
      }
      Inspec::DependencySet.from_lockfile(lockfile, config, { inputs: @input_values })
    end

    # Calculate this profile's SHA256 checksum. Includes metadata, dependencies,
    # libraries, data files, and controls.
    #
    # @return [Type] description of returned object
    def sha256
      # get all dependency checksums
      deps = Hash[locked_dependencies.list.map { |k, v| [k, v.profile.sha256] }]

      res = OpenSSL::Digest.new("SHA256")
      files = source_reader.tests.to_a + source_reader.libraries.to_a +
        source_reader.data_files.to_a +
        [["inspec.yml", source_reader.metadata.content]] +
        [["inspec.lock.deps", YAML.dump(deps)]]

      files.sort_by { |a| a[0] }
        .map { |f| res << f[0] << "\0" << f[1] << "\0" }

      res.digest.unpack("H*")[0]
    end

    private

    # Create an archive name for this profile and an additional options
    # configuration. Either use :output or generate the name from metadata.
    #
    # @param [Hash] configuration options
    # @return [Pathname] path for the archive
    def archive_name(opts)
      if (name = opts[:output])
        return Pathname.new(name)
      end

      name = params[:name] ||
        raise("Cannot create an archive without a profile name! Please "\
             "specify the name in metadata or use --output to create the archive.")
      version = params[:version] ||
        raise("Cannot create an archive without a profile version! Please "\
             "specify the version in metadata or use --output to create the archive.")
      ext = opts[:zip] ? "zip" : "tar.gz"
      slug = name.downcase.strip.tr(" ", "-").gsub(/[^\w-]/, "_")
      Pathname.new(Dir.pwd).join("#{slug}-#{version}.#{ext}")
    end

    def load_params
      params = @source_reader.metadata.params
      params[:name] = @profile_id unless @profile_id.nil?
      load_checks_params(params)
      @profile_id ||= params[:name]
      params
    end

    def load_checks_params(params)
      load_libraries
      tests = collect_tests
      params[:controls] = controls = {}
      params[:groups] = groups = {}
      prefix = @source_reader.target.prefix || ""
      tests&.each do |rule|
        next if rule.nil?

        f = load_rule_filepath(prefix, rule)
        load_rule(rule, f, controls, groups)
      end
      params[:inputs] = Inspec::InputRegistry.list_inputs_for_profile(@profile_id)
      params
    end

    def load_rule_filepath(prefix, rule)
      file = rule.instance_variable_get(:@__file)
      file = file[prefix.length..-1] if file.start_with?(prefix)
      file
    end

    def load_rule(rule, file, controls, groups)
      id = Inspec::Rule.rule_id(rule)
      location = rule.instance_variable_get(:@__source_location)
      controls[id] = {
        title: rule.title,
        desc: rule.desc,
        descriptions: rule.descriptions,
        impact: rule.impact,
        refs: rule.ref,
        tags: rule.tag,
        checks: Inspec::Rule.checks(rule),
        code: Inspec::MethodSource.code_at(location, source_reader),
        source_location: location,
      }

      # try and grab code text from merge locations
      if controls[id][:code].empty? && Inspec::Rule.merge_count(rule) > 0
        Inspec::Rule.merge_changes(rule).each do |merge_location|
          code = Inspec::MethodSource.code_at(merge_location, source_reader)
          unless code.empty?
            controls[id][:code] = code
            break
          end
        end
      end

      groups[file] ||= {
        title: rule.instance_variable_get(:@__group_title),
        controls: [],
      }
      groups[file][:controls].push(id)
    end
  end
end
