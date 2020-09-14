require "inspec/log"
require "inspec/version"
require "inspec/plugin/v2/config_file"
require "inspec/plugin/v2/filter"

module Inspec::Plugin::V2
  class Loader
    attr_reader :conf_file, :registry, :options

    # For {inspec|train}_plugin_name?
    include Inspec::Plugin::V2::FilterPredicates
    extend Inspec::Plugin::V2::FilterPredicates

    def initialize(options = {})
      @options = options
      @registry = Inspec::Plugin::V2::Registry.instance

      # User plugins are those installed by the user via `inspec plugin install`
      # and are installed under ~/.inspec/gems
      unless options[:omit_user_plugins]
        @conf_file = Inspec::Plugin::V2::ConfigFile.new
        read_conf_file_into_registry
      end

      # Old-style (v0, v1) co-distributed plugins were called 'bundles'
      # and were located in lib/bundles
      detect_bundled_plugins unless options[:omit_bundles]

      # New-style (v2) co-distributed plugins are in lib/plugins,
      # and may be safely loaded
      detect_core_plugins unless options[:omit_core_plugins]

      # Identify plugins that inspec is co-installed with
      detect_system_plugins unless options[:omit_sys_plugins]

      # Train plugins are not true InSpec plugins; we need to decorate them a
      # bit more to integrate them. Wait to do this until after we know if
      # they are system or user.
      registry.each do |plugin_name, status|
        fixup_train_plugin_status(status) if train_plugin_name?(plugin_name)
      end
    end

    def load_all
      # This fixes the gem paths on some bundles
      Gem.path << plugin_gem_path
      Gem.refresh

      # Be careful not to actually iterate directly over the registry here;
      # we want to allow "sidecar loading", in which case a plugin may add an entry to the registry.
      registry.plugin_names.dup.each do |plugin_name|
        # Skip plugins bundled with profiles, which get loaded automatically
        next if registry.profile_bundled_plugin?(plugin_name)

        plugin_details = registry[plugin_name]
        # We want to capture literally any possible exception here, since we are storing them.
        # rubocop: disable Lint/RescueException
        begin
          # We could use require, but under testing, we need to repeatedly reload the same
          # plugin.  However, gems only work with require (rubygems dooes not overload `load`)
          case plugin_details.installation_type
          when :user_gem
            activate_managed_gems_for_plugin(plugin_name)
            require plugin_details.entry_point
          when :system_gem
            require plugin_details.entry_point
          else
            load_path = plugin_details.entry_point
            load_path += ".rb" unless plugin_details.entry_point.end_with?(".rb")
            load load_path
          end
          plugin_details.loaded = true
          annotate_status_after_loading(plugin_name)
        rescue ::Exception => ex
          plugin_details.load_exception = ex
          Inspec::Log.error "Could not load plugin #{plugin_name}: #{ex.message}"
        end
        # rubocop: enable Lint/RescueException
      end
    end

    # This should possibly be in either lib/inspec/cli.rb or Registry
    def exit_on_load_error
      if registry.any_load_failures?
        Inspec::Log.error "Errors were encountered while loading plugins..."
        registry.plugin_statuses.select(&:load_exception).each do |plugin_status|
          Inspec::Log.error "Plugin name: " + plugin_status.name.to_s
          Inspec::Log.error "Error: " + plugin_status.load_exception.message
          if ARGV.include?("--debug")
            Inspec::Log.error "Exception: " + plugin_status.load_exception.class.name
            Inspec::Log.error "Trace: " + plugin_status.load_exception.backtrace.join("\n")
          end
        end
        Inspec::Log.error("Run again with --debug for a stacktrace.") unless ARGV.include?("--debug")
        exit 2
      end
    end

    def activate_mentioned_cli_plugins(cli_args = ARGV)
      # Get a list of CLI plugin activation hooks
      registry.find_activators(plugin_type: :cli_command).each do |act|
        next if act.activated?

        # Decide whether to activate.  Several conditions, so split them out for clarity.
        # Assume no, to start.  Each condition may flip it true, which will short-circuit
        # all following ||= ops.
        activate_me = false

        # If the user invoked `inspec help`, `inspec --help`, or only `inspec`
        # then activate all CLI plugins so they can display their usage message.
        activate_me ||= ["help", "--help", nil].include?(cli_args.first)

        # If there is anything in the CLI args with the same name, activate it.
        # This is the expected usual activation for individual plugins.
        # `inspec dosomething` => activate the :dosomething hook
        activate_me ||= cli_args.include?(act.activator_name.to_s)

        # OK, activate.
        if activate_me
          act.activate
          act.implementation_class.register_with_thor
        end
      end
    end

    def plugin_gem_path
      self.class.plugin_gem_path
    end

    def self.plugin_gem_path
      require "rbconfig"
      ruby_abi_version = RbConfig::CONFIG["ruby_version"]
      # TODO: why are we installing under the api directory for plugins?
      base_dir = Inspec.config_dir
      base_dir = File.realpath base_dir if File.exist? base_dir
      File.join(base_dir, "gems", ruby_abi_version)
    end

    # Lists all gems found in the plugin_gem_path.
    # @return [Array[Gem::Specification]] Specs of all gems found.
    def self.list_managed_gems
      Dir.glob(File.join(plugin_gem_path, "specifications", "*.gemspec")).map { |p| Gem::Specification.load(p) }
    end

    def list_managed_gems
      self.class.list_managed_gems
    end

    # Lists all plugin gems found in the plugin_gem_path.
    # This is simply all gems that begin with train- or inspec-
    # and are not on the exclusion list.
    # @return [Array[Gem::Specification]] Specs of all gems found.
    def self.list_installed_plugin_gems
      list_managed_gems.select { |spec| valid_plugin_name?(spec.name) }
    end

    def list_installed_plugin_gems
      self.class.list_managed_gems
    end

    private

    # 'Activating' a gem adds it to the load path, so 'require "gemname"' will work.
    # Given a gem name, this activates the gem and all of its dependencies, respecting
    # version pinning needs.
    def activate_managed_gems_for_plugin(plugin_gem_name, version_constraint = "> 0")
      # TODO: enforce first-level version pinning
      plugin_deps = [Gem::Dependency.new(plugin_gem_name.to_s, version_constraint)]
      managed_gem_set = Gem::Resolver::VendorSet.new
      list_managed_gems.each { |spec| managed_gem_set.add_vendor_gem(spec.name, spec.gem_dir) }

      # TODO: Next two lines merge our managed gems with the other gems available
      # in our "local universe" - which may be the system, or it could be in a Bundler microcosm,
      # or rbenv, etc. Do we want to merge that, though?
      distrib_gem_set = Gem::Resolver::CurrentSet.new
      installed_gem_set = Gem::Resolver.compose_sets(managed_gem_set, distrib_gem_set)

      # So, given what we need, and what we have available, what activations are needed?
      resolver = Gem::Resolver.new(plugin_deps, installed_gem_set)
      begin
        solution = resolver.resolve
      rescue Gem::UnsatisfiableDependencyError => gem_ex
        # If you broke your install, or downgraded to a plugin with a bad gemspec, you could get here.
        ex = Inspec::Plugin::V2::LoadError.new(gem_ex.message)
        raise ex
      end
      solution.each do |activation_request|
        next if activation_request.full_spec.activated?

        activation_request.full_spec.activate
        # TODO: If we are under Bundler, inform it that we loaded a gem
      end
    end

    def annotate_status_after_loading(plugin_name)
      status = registry[plugin_name]
      return if status.api_generation == 2 # Gen2 have self-annotating superclasses
      return if status.api_generation == :'train-1' # Train plugins are here as a courtesy, don't poke them

      case status.installation_type
      when :bundle
        annotate_bundle_plugin_status_after_load(plugin_name)
      else
        # TODO: are there any other cases? can this whole thing be eliminated?
        raise "I only know how to annotate :bundle plugins when trying to load plugin #{plugin_name}" unless status.installation_type == :bundle
      end
    end

    def annotate_bundle_plugin_status_after_load(plugin_name)
      # HACK: we're relying on the fact that all bundles are gen0 and cli type
      status = registry[plugin_name]
      status.api_generation = 0
      act = Activator.new
      act.activated = true
      act.plugin_type = :cli_command
      act.plugin_name = plugin_name
      act.activator_name = :default
      status.activators = [act]

      v0_subcommand_name = plugin_name.to_s.gsub("inspec-", "")
      status.plugin_class = Inspec::Plugins::CLI.subcommands[v0_subcommand_name][:klass]
    end

    def detect_bundled_plugins
      bundle_dir = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "bundles"))
      globs = [
        File.join(bundle_dir, "inspec-*.rb"),
        File.join(bundle_dir, "train-*.rb"),
      ]
      Dir.glob(globs).each do |loader_file|
        name = File.basename(loader_file, ".rb").to_sym
        status = Inspec::Plugin::V2::Status.new
        status.name = name
        status.entry_point = loader_file
        status.installation_type = :bundle
        status.loaded = false
        registry[name] = status
      end
    end

    def detect_core_plugins
      core_plugins_dir = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "plugins"))
      # These are expected to be organized as proper separate projects,
      # with lib/ dirs, etc.
      Dir.glob(File.join(core_plugins_dir, "inspec-*")).each do |plugin_dir|
        status = Inspec::Plugin::V2::Status.new
        status.name = File.basename(plugin_dir).to_sym
        status.entry_point = File.join(plugin_dir, "lib", status.name.to_s + ".rb")
        status.installation_type = :core
        status.loaded = false
        registry[status.name.to_sym] = status
      end
    end

    def read_conf_file_into_registry
      conf_file.each do |plugin_entry|
        status = Inspec::Plugin::V2::Status.new
        status.name = plugin_entry[:name]
        status.loaded = false
        status.installation_type = (plugin_entry[:installation_type] || :user_gem)
        case status.installation_type
        when :user_gem
          status.entry_point = status.name.to_s
          status.version = plugin_entry[:version]
        when :path
          status.entry_point = plugin_entry[:installation_path]
        end

        registry[status.name] = status
      end
    end

    def fixup_train_plugin_status(status)
      status.api_generation = :'train-1'
      if status.installation_type == :user_gem
        # Activate the gem. This allows train to 'require' the gem later.
        # This is not required for system gems because rubygems already has
        # activated the gemspecs.
        activate_managed_gems_for_plugin(status.entry_point)
      end
    end

    def find_inspec_gemspec(name, ver)
      Gem::Specification.find_by_name(name, ver)
    rescue Gem::MissingSpecError
      nil
    end

    def detect_system_plugins
      # Find the gemspec for inspec
      inspec_gemspec =
        find_inspec_gemspec("inspec",      "=#{Inspec::VERSION}") ||
        find_inspec_gemspec("inspec-core", "=#{Inspec::VERSION}")

      unless inspec_gemspec
        Inspec::Log.warn "inspec gem not found, skipping detecting of system plugins"
        return
      end

      # Make a RequestSet that represents the dependencies of inspec
      inspec_deps_request_set = Gem::RequestSet.new(*inspec_gemspec.dependencies)
      inspec_deps_request_set.remote = false

      # Resolve the request against the installed gem universe
      gem_resolver = Gem::Resolver::CurrentSet.new
      runtime_solution = inspec_deps_request_set.resolve(gem_resolver)

      inspec_gemspec.dependencies.each do |inspec_dep|
        next unless inspec_plugin_name?(inspec_dep.name) || train_plugin_name?(inspec_dep.name)

        plugin_spec = runtime_solution.detect { |s| s.name == inspec_dep.name }.spec

        status = Inspec::Plugin::V2::Status.new
        status.name = inspec_dep.name
        status.entry_point = inspec_dep.name # gem-based, just 'require' the name
        status.version = plugin_spec.version.to_s
        status.loaded = false
        status.installation_type = :system_gem

        if train_plugin_name?(status[:name])
          # Train plugins are not true InSpec plugins; we need to decorate them a
          # bit more to integrate them.
          fixup_train_plugin_status(status)
        else
          status.api_generation = 2
        end

        registry[status.name.to_sym] = status
      end
    end
  end
end
