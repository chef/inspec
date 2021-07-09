require "thor" # rubocop:disable Chef/Ruby/UnlessDefinedRequire
require "inspec/log"
require "inspec/ui"
require "inspec/config"
require "inspec/dist"
require "inspec/utils/deprecation/global_method"

# Allow end of options during array type parsing
# https://github.com/erikhuda/thor/issues/631
class Thor::Arguments
  alias old_parse_array parse_array

  def parse_array(_name)
    return shift if peek.is_a?(Array)

    array = []
    while current_is_value?
      break unless @parsing_options

      array << shift
    end
    array
  end
end

module Inspec
  class BaseCLI < Thor
    class << self
      attr_accessor :inspec_cli_command
    end

    def self.start(given_args = ARGV, config = {})
      check_license! if config[:enforce_license] || config[:enforce_license].nil?

      super(given_args, config)
    end

    # EULA acceptance
    def self.check_license!
      allowed_commands = ["-h", "--help", "help", "-v", "--version", "version"]

      require "license_acceptance/acceptor"
      begin
        if (allowed_commands & ARGV.map(&:downcase)).empty? && # Did they use a non-exempt command?
            !ARGV.empty? # Did they supply at least one command?
          LicenseAcceptance::Acceptor.check_and_persist(
            Inspec::Dist::EXEC_NAME,
            Inspec::VERSION,
            logger: Inspec::Log
          )
        end
      rescue LicenseAcceptance::LicenseNotAcceptedError
        Inspec::Log.error "#{Inspec::Dist::PRODUCT_NAME} cannot execute without accepting the license"
        Inspec::UI.new.exit(:license_not_accepted)
      end
    end

    # https://github.com/erikhuda/thor/issues/244
    def self.exit_on_failure?
      true
    end

    def self.target_options # rubocop:disable Metrics/MethodLength
      option :target, aliases: :t, type: :string,
        desc: "Simple targeting option using URIs, e.g. ssh://user:pass@host:port"
      option :backend, aliases: :b, type: :string,
        desc: "Choose a backend: local, ssh, winrm, docker."
      option :host, type: :string,
        desc: "Specify a remote host which is tested."
      option :port, aliases: :p, type: :numeric,
        desc: "Specify the login port for a remote scan."
      option :user, type: :string,
        desc: "The login user for a remote scan."
      option :password, type: :string, lazy_default: -1,
        desc: "Login password for a remote scan, if required."
      option :enable_password, type: :string, lazy_default: -1,
        desc: "Password for enable mode on Cisco IOS devices."
      option :key_files, aliases: :i, type: :array,
        desc: "Login key or certificate file for a remote scan."
      option :path, type: :string,
        desc: "Login path to use when connecting to the target (WinRM)."
      option :sudo, type: :boolean,
        desc: "Run scans with sudo. Only activates on Unix and non-root user."
      option :sudo_password, type: :string, lazy_default: -1,
        desc: "Specify a sudo password, if it is required."
      option :sudo_options, type: :string,
        desc: "Additional sudo options for a remote scan."
      option :sudo_command, type: :string,
        desc: "Alternate command for sudo."
      option :shell, type: :boolean,
        desc: "Run scans in a subshell. Only activates on Unix."
      option :shell_options, type: :string,
        desc: "Additional shell options."
      option :shell_command, type: :string,
        desc: "Specify a particular shell to use."
      option :ssl, type: :boolean,
        desc: "Use SSL for transport layer encryption (WinRM)."
      option :self_signed, type: :boolean,
        desc: "Allow remote scans with self-signed certificates (WinRM)."
      option :winrm_transport, type: :string, default: "negotiate",
        desc: "Specify which transport to use, defaults to negotiate (WinRM)."
      option :winrm_disable_sspi, type: :boolean,
        desc: "Whether to use disable sspi authentication, defaults to false (WinRM)."
      option :winrm_basic_auth_only, type: :boolean,
        desc: "Whether to use basic authentication, defaults to false (WinRM)."
      option :config, type: :string,
        desc: "Read configuration from JSON file (`-` reads from stdin)."
      option :json_config, type: :string, hide: true
      option :proxy_command, type: :string,
        desc: "Specifies the command to use to connect to the server"
      option :bastion_host, type: :string,
        desc: "Specifies the bastion host if applicable"
      option :bastion_user, type: :string,
        desc: "Specifies the bastion user if applicable"
      option :bastion_port, type: :string,
        desc: "Specifies the bastion port if applicable"
      option :insecure, type: :boolean, default: false,
        desc: "Disable SSL verification on select targets"
      option :target_id, type: :string,
        desc: "Provide a ID which will be included on reports"
      option :winrm_shell_type, type: :string, default: "powershell",
        desc: "Specify a shell type for winrm (eg. 'elevated' or 'powershell')"
      option :docker_url, type: :string,
        desc: "Provides path to Docker API endpoint (Docker)"
    end

    def self.profile_options
      option :profiles_path, type: :string,
        desc: "Folder which contains referenced profiles."
      option :vendor_cache, type: :string,
        desc: "Use the given path for caching dependencies. (default: ~/.inspec/cache)"
    end

    def self.exec_options
      target_options
      profile_options
      option :controls, type: :array,
        desc: "A list of control names to run, or a list of /regexes/ to match against control names. Ignore all other tests."
      option :tags, type: :array,
        desc: "A list of tags names that are part of controls to filter and run controls, or a list of /regexes/ to match against tags names of controls. Ignore all other tests."
      option :reporter, type: :array,
        banner: "one two:/output/file/path",
        desc: "Enable one or more output reporters: cli, documentation, html, progress, json, json-min, json-rspec, junit, yaml"
      option :reporter_message_truncation, type: :string,
        desc: "Number of characters to truncate failure messages and code_desc in report data to (default: no truncation)"
      option :reporter_backtrace_inclusion, type: :boolean,
        desc: "Include a code backtrace in report data (default: true)"
      option :input, type: :array, banner: "name1=value1 name2=value2",
        desc: "Specify one or more inputs directly on the command line, as --input NAME=VALUE. Accepts single-quoted YAML and JSON structures."
      option :input_file, type: :array,
        desc: "Load one or more input files, a YAML file with values for the profile to use"
      option :waiver_file, type: :array,
        desc: "Load one or more waiver files."
      option :attrs, type: :array,
        desc: "Legacy name for --input-file - deprecated."
      option :create_lockfile, type: :boolean,
        desc: "Write out a lockfile based on this execution (unless one already exists)"
      option :backend_cache, type: :boolean,
        desc: "Allow caching for backend command output. (default: true)"
      option :show_progress, type: :boolean,
        desc: "Show progress while executing tests."
      option :distinct_exit, type: :boolean, default: true,
        desc: "Exit with code 101 if any tests fail, and 100 if any are skipped (default).  If disabled, exit 0 on skips and 1 for failures."
      option :silence_deprecations, type: :array,
        banner: "[all]|[GROUP GROUP...]",
        desc: "Suppress deprecation warnings. See install_dir/etc/deprecations.json for list of GROUPs or use 'all'."
      option :diff, type: :boolean, default: true,
        desc: "Use --no-diff to suppress 'diff' output of failed textual test results."
      option :sort_results_by, type: :string, default: "file", banner: "--sort-results-by=none|control|file|random",
        desc: "After normal execution order, results are sorted by control ID, or by file (default), or randomly. None uses legacy unsorted mode."
      option :filter_empty_profiles, type: :boolean, default: false,
        desc: "Filter empty profiles (profiles without controls) from the report."
      option :command_timeout, type: :numeric,
        desc: "Maximum seconds to allow commands to run during execution.",
        long_desc: "Maximum seconds to allow commands to run during execution. A timed out command is considered an error."
      option :reporter_include_source, type: :boolean, default: false,
        desc: "Include full source code of controls in the CLI report"
    end

    def self.help(*args)
      super(*args)
      puts "\nAbout #{Inspec::Dist::PRODUCT_NAME}:"
      puts "  Patents: chef.io/patents\n\n"
    end

    def self.format_platform_info(params: {}, indent: 0, color: 39, enable_color: true)
      str = ""
      params.each do |item, info|
        data = info

        # Format Array for better output if applicable
        data = data.join(", ") if data.is_a?(Array)

        # Do not output fields of data is missing ('unknown' is fine)
        next if data.nil?

        data = "\e[1m\e[#{color}m#{data}\e[0m" if enable_color
        str << format("#{" " * indent}%-10s %s\n", item.to_s.capitalize + ":", data)
      end
      str
    end

    # These need to be public methods on any BaseCLI instance,
    # but Thor interprets all methods as subcommands.  The no_commands block
    # treats them as regular methods.
    no_commands do
      def ui
        return @ui if defined?(@ui)

        # Make a new UI object, respecting context
        if options[:color].nil?
          enable_color = true # If the command does not support the color option, default to on
        else
          enable_color = options[:color]
        end

        # UI will probe for TTY if nil - just send the raw option value
        enable_interactivity = options[:interactive]

        @ui = Inspec::UI.new(color: enable_color, interactive: enable_interactivity)
      end

      # Rationale: converting this to attr_writer breaks Thor
      def ui=(new_ui) # rubocop: disable Style/TrivialAccessors
        @ui = new_ui
      end

      def mark_text(text)
        Inspec.deprecate(:inspec_ui_methods)
        # Note that this one doesn't automatically print
        ui.emphasis(text, print: false)
      end

      def headline(title)
        Inspec.deprecate(:inspec_ui_methods)
        ui.headline(title)
      end

      def li(entry)
        Inspec.deprecate(:inspec_ui_methods)
        ui.list_item(entry)
      end

      def plain_text(msg)
        Inspec.deprecate(:inspec_ui_methods)
        ui.plain(msg + "\n")
      end

      def exit(code)
        Inspec.deprecate(:inspec_ui_methods)
        ui.exit code
      end
    end

    private

    ALL_OF_OUR_REPORTERS = %w{json json-min json-rspec json-automate junit html html2 yaml documentation progress}.freeze # BUT WHY?!?!

    def suppress_log_output?(opts)
      return false if opts["reporter"].nil?

      match = ALL_OF_OUR_REPORTERS & opts["reporter"].keys

      unless match.empty?
        match.each do |m|
          # check to see if we are outputting to stdout
          return true if opts["reporter"][m]["stdout"] == true
        end
      end

      false
    end

    def diagnose(_ = nil)
      config.diagnose
    end

    def config
      @config ||= Inspec::Config.new(options) # 'options' here is CLI opts from Thor
    end

    # get the log level
    # DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
    def get_log_level(level)
      valid = %w{debug info warn error fatal}

      if valid.include?(level)
        l = level
      else
        l = "info"
      end

      Logger.const_get(l.upcase)
    end

    def pretty_handle_exception(exception)
      case exception
      when Inspec::Error
        $stderr.puts exception.message
        exit(1)
      else
        raise exception
      end
    end

    def vendor_deps(path, opts)
      require "inspec/profile_vendor"

      profile_path = path || Dir.pwd
      profile_vendor = Inspec::ProfileVendor.new(profile_path)

      if (profile_vendor.cache_path.exist? || profile_vendor.lockfile.exist?) && !opts[:overwrite]
        puts "Profile is already vendored. Use --overwrite."
        return false
      end

      profile_vendor.vendor!(opts)
      puts "Dependencies for profile #{profile_path} successfully vendored to #{profile_vendor.cache_path}"
    rescue StandardError => e
      pretty_handle_exception(e)
    end

    def configure_logger(o)
      #
      # TODO(ssd): This is a bit gross, but this configures the
      # logging singleton Inspec::Log. Eventually it would be nice to
      # move internal debug logging to use this logging singleton.
      #
      loc = if o["log_location"]
              o["log_location"]
            elsif suppress_log_output?(o)
              $stderr
            else
              $stdout
            end

      Inspec::Log.init(loc)
      Inspec::Log.level = get_log_level(o["log_level"])

      o[:logger] = Logger.new(loc)
      # output json if we have activated the json formatter
      if o["log-format"] == "json"
        o[:logger].formatter = Logger::JSONFormatter.new
      end
      o[:logger].level = get_log_level(o["log_level"])
    end
  end
end
