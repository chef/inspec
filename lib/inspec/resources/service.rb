require "hashie"
require "inspec/utils/file_reader"
require "inspec/utils/simpleconfig"

module Inspec::Resources
  class Runlevels < Hash
    attr_accessor :owner

    def self.from_hash(owner, hash = {}, filter = nil)
      res = Runlevels.new(owner)
      filter = filter.first if filter.is_a?(Array) && filter.length <= 1

      ks = case filter
           when nil
             hash.keys
           when Regexp
             hash.keys.find_all { |x| x.to_s =~ filter }
           when Array
             f = filter.map(&:to_s)
             hash.keys.find_all { |x| f.include?(x.to_s) }
           when Numeric
             hash.keys.include?(filter) ? [filter] : []
           else
             hash.keys.find_all { |x| x == filter }
           end

      ks.each { |k| res[k] = hash[k] }
      res
    end

    def initialize(owner, default = false)
      @owner = owner
      super(default)
    end

    def filter(f)
      Runlevels.from_hash(owner, self, f)
    end

    # Check if all runlevels are enabled
    #
    # @return [boolean] true if all runlevels are enabled
    def enabled?
      values.all?
    end

    # Check if all runlevels are disabled
    #
    # @return [boolean] true if all runlevels are disabled
    def disabled?
      values.none?
    end

    def to_s
      "#{owner} runlevels #{keys.join(", ")}"
    end
  end

  # We detect the init system for each operating system, based on the operating
  # system.
  #
  # Fedora 15 : systemd
  # RedHat 7 : systemd
  # Ubuntu 15.04 : systemd
  # Ubuntu < 15.04 : upstart
  #
  # TODO: extend the logic to detect the running init system, independently of OS
  class Service < Inspec.resource(1)
    name "service"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the service InSpec audit resource to test if the named service is installed, running and/or enabled."
    example <<~EXAMPLE
      describe service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
        its('type') { should be 'systemd' }
        its ('startmode') { should be 'Auto'}
      end

      describe service('service_name').runlevels(3, 5) do
        it { should be_enabled }
      end

      describe service('service_name').params do
        its('UnitFileState') { should eq 'enabled' }
      end
    EXAMPLE

    attr_reader :service_ctl

    def initialize(service_name, service_ctl = nil)
      @service_name = service_name
      @service_mgmt = nil
      @service_ctl ||= service_ctl
      @cache = nil
      @service_mgmt = select_service_mgmt

      return skip_resource "The `service` resource is not supported on your OS yet." if @service_mgmt.nil?
    end

    def select_service_mgmt # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      os = inspec.os
      platform = os[:name]

      return WindowsSrv.new(inspec) if os.windows?

      # Ubuntu
      # @see: https://wiki.ubuntu.com/SystemdForUpstartUsers
      # Ubuntu 15.04 : Systemd
      #   Systemd runs with PID 1 as /sbin/init.
      #   Upstart runs with PID 1 as /sbin/upstart.
      # Ubuntu < 15.04 : Upstart
      # Upstart runs with PID 1 as /sbin/init.
      # Systemd runs with PID 1 as /lib/systemd/systemd.

      case platform
      when "ubuntu"
        version = os[:release].to_f
        if version < 15.04
          Upstart.new(inspec, service_ctl)
        else
          Systemd.new(inspec, service_ctl)
        end
      when "linuxmint"
        version = os[:release].to_f
        if version < 18
          Upstart.new(inspec, service_ctl)
        else
          Systemd.new(inspec, service_ctl)
        end
      when "debian"
        if os[:release] == "buster/sid"
          version = 10
        else
          version = os[:release].to_i
        end
        if version > 7
          Systemd.new(inspec, service_ctl)
        elsif version > 0
          SysV.new(inspec, service_ctl || "/usr/sbin/service")
        end
      when "redhat", "fedora", "centos", "oracle", "cloudlinux", "scientific"
        version = os[:release].to_i

        systemd = ((platform != "fedora" && version >= 7) ||
                   (platform == "fedora" && version >= 15))

        if systemd
          Systemd.new(inspec, service_ctl)
        else
          SysV.new(inspec, service_ctl || "/sbin/service")
        end
      when "alibaba"
        if os[:release].to_i >= 3
          Systemd.new(inspec, service_ctl)
        else
          SysV.new(inspec, service_ctl || "/sbin/service")
        end
      when "wrlinux"
        SysV.new(inspec, service_ctl)
      when "mac_os_x", "darwin"
        LaunchCtl.new(inspec, service_ctl)
      when "freebsd"
        BSDInit.new(inspec, service_ctl)
      when "arch"
        Systemd.new(inspec, service_ctl)
      when "coreos"
        Systemd.new(inspec, service_ctl)
      when "suse", "opensuse"
        if os[:release].to_i >= 12
          Systemd.new(inspec, service_ctl)
        else
          SysV.new(inspec, service_ctl || "/sbin/service")
        end
      when "aix"
        SrcMstr.new(inspec)
      when "amazon"
        if os[:release] =~ /^20\d\d/
          Upstart.new(inspec, service_ctl)
        else
          Systemd.new(inspec, service_ctl)
        end
      when "solaris", "smartos", "omnios", "openindiana", "opensolaris", "nexentacore"
        Svcs.new(inspec)
      when "yocto"
        Systemd.new(inspec, service_ctl)
      end
    end

    def info
      return nil if @service_mgmt.nil?

      @cache ||= @service_mgmt.info(@service_name)
    end

    # verifies if the service is enabled
    def enabled?(_level = nil)
      return false if info.nil?

      info[:enabled]
    end

    def params
      return {} if info.nil?

      Hashie::Mash.new(info[:params] || {})
    end

    # verifies the service is registered
    def installed?(_name = nil, _version = nil)
      return false if info.nil?

      info[:installed]
    end

    # verifies the service is currently running
    def running?(_under = nil)
      return false if info.nil?

      info[:running]
    end

    # get all runlevels that are available and their configuration
    def runlevels(*args)
      return Runlevels.new(self) if info.nil? || info[:runlevels].nil?

      Runlevels.from_hash(self, info[:runlevels], args)
    end

    # returns the service type from info
    def type
      return nil if info.nil?

      info[:type]
    end

    # returns the service name from info
    def name
      return @service_name if info.nil?

      info[:name]
    end

    # returns the service description from info
    def description
      return nil if info.nil?

      info[:description]
    end

    # returns the service start up mode from info
    def startmode
      return nil if info.nil?

      info[:startmode]
    end

    # returns the service's user from info
    def startname
      return nil if info.nil?

      info[:startname]
    end

    def to_s
      "Service #{@service_name}"
    end

    private :info
  end

  class ServiceManager
    attr_reader :inspec, :service_ctl
    def initialize(inspec, service_ctl = nil)
      @inspec = inspec
      @service_ctl ||= service_ctl
    end
  end

  # @see: http://www.freedesktop.org/software/systemd/man/systemctl.html
  # @see: http://www.freedesktop.org/software/systemd/man/systemd-system.conf.html
  class Systemd < ServiceManager
    def initialize(inspec, service_ctl = nil)
      @service_ctl = service_ctl || "systemctl"
      super
    end

    def is_enabled?(service_name)
      result = inspec.command("#{service_ctl} is-enabled #{service_name} --quiet")
      return true if result.exit_status == 0

      # Some systems may not have a `.service` file for a particular service
      # which causes the `systemctl is-enabled` check to fail despite the
      # service being enabled. In that event we fallback to `sysv_service`.
      if result.stderr =~ /Failed to get.*No such file or directory/
        return inspec.sysv_service(service_name).enabled?
      end

      false
    end

    def is_active?(service_name)
      inspec.command("#{service_ctl} is-active #{service_name} --quiet").exit_status == 0
    end

    def info(service_name)
      cmd = inspec.command("#{service_ctl} show --no-pager --all #{service_name}")
      return nil if cmd.exit_status.to_i != 0

      # parse data
      params = SimpleConfig.new(
        cmd.stdout.chomp,
        assignment_regex: /^\s*([^=]*?)\s*=\s*(.*?)\s*$/,
        multiple_values: false
      ).params

      # LoadState values eg. loaded, not-found
      installed = params["LoadState"] == "loaded"
      startname = params["User"]

      {
        name: params["Id"],
        description: params["Description"],
        startname: startname,
        installed: installed,
        running: is_active?(service_name),
        enabled: is_enabled?(service_name),
        type: "systemd",
        params: params,
      }
    end
  end

  # AIX services
  class SrcMstr < ServiceManager
    attr_reader :name

    def info(service_name)
      @name = service_name
      running = status?
      return nil if running.nil?

      {
        name: service_name,
        description: nil,
        installed: true,
        running: running,
        enabled: enabled?,
        type: "srcmstr",
      }
    end

    private

    def status?
      status_cmd = inspec.command("lssrc -s #{@name}")
      return nil if status_cmd.exit_status.to_i != 0

      status_cmd.stdout.split(/\n/).last.chomp =~ /active$/ ? true : false
    end

    def enabled?
      enabled_rc_tcpip? || enabled_inittab?
    end

    def enabled_rc_tcpip?
      inspec.command(
        "grep -v ^# /etc/rc.tcpip | grep 'start ' | grep -Eq '(/{0,1}| )#{name} '"
      ).exit_status == 0
    end

    def enabled_inittab?
      inspec.command("lsitab #{name}").exit_status == 0
    end
  end

  # @see: http://upstart.ubuntu.com
  class Upstart < ServiceManager
    include FileReader

    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "initctl"
      super
    end

    def info(service_name)
      # get the status of upstart service
      status = inspec.command("#{service_ctl} status #{service_name}")

      # fallback for systemv services, those are not handled via `initctl`
      return SysV.new(inspec).info(service_name) if status.exit_status.to_i != 0 || status.stdout == ""

      # @see: http://upstart.ubuntu.com/cookbook/#job-states
      # grep for running to indicate the service is there
      running = !status.stdout[%r{start/running}].nil?
      enabled = info_enabled(service_name)

      {
        name: service_name,
        description: nil,
        installed: true,
        running: running,
        enabled: enabled,
        type: "upstart",
      }
    end

    private

    def info_enabled(service_name)
      # check if a service is enabled
      config = read_file_content("/etc/init/#{service_name}.conf", allow_empty: true)

      !config.match(/^\s*start on/).nil?
    end

    def version
      @version ||= begin
        out = inspec.command("#{service_ctl} --version").stdout
        Gem::Version.new(out[/\(upstart ([^\)]+)\)/, 1])
      end
    end
  end

  class SysV < ServiceManager
    RUNLEVELS = { 0 => false, 1 => false, 2 => false, 3 => false, 4 => false, 5 => false, 6 => false }.freeze

    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "service"
      super
    end

    def info(service_name)
      # check if service is installed
      # read all available services via ls /etc/init.d/
      srvlist = inspec.command("ls -1 /etc/init.d/")
      return nil if srvlist.exit_status != 0

      # check if the service is in list
      service = srvlist.stdout.split("\n").select { |srv| srv == service_name }

      # abort if we could not find any service
      return nil if service.empty?

      # read all enabled services from runlevel
      # on rhel via: 'chkconfig --list', is not installed by default
      # bash: for i in `find /etc/rc*.d -name S*`; do basename $i | sed -r 's/^S[0-9]+//'; done | sort | uniq
      enabled_services_cmd = inspec.command('find /etc/rc*.d /etc/init.d/rc*.d -name "S*"').stdout
      service_line = %r{rc(?<runlevel>[0-6])\.d/S[^/]*?#{Regexp.escape service_name}$}
      all_services = enabled_services_cmd.split("\n").map do |line|
        service_line.match(line)
      end.compact
      enabled = !all_services.empty?

      # Determine a list of runlevels which this service is activated for
      runlevels = RUNLEVELS.dup
      all_services.each { |x| runlevels[x[:runlevel].to_i] = true }

      # check if service is really running
      # service throws an exit code if the service is not installed or
      # not enabled

      cmd = inspec.command("#{service_ctl} #{service_name} status")
      running = cmd.exit_status == 0
      {
        name: service_name,
        description: nil,
        installed: true,
        running: running,
        enabled: enabled,
        runlevels: runlevels,
        type: "sysv",
      }
    end
  end

  # @see: https://www.freebsd.org/doc/en/articles/linux-users/startup.html
  # @see: https://www.freebsd.org/cgi/man.cgi?query=rc.conf&sektion=5
  class BSDInit < ServiceManager
    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "service"
      super
    end

    def info(service_name)
      # check if service is enabled
      # services are enabled in /etc/rc.conf and /etc/defaults/rc.conf
      # via #{service_name}_enable="YES"
      # service SERVICE status returns the following result if not activated:
      #   Cannot 'status' sshd. Set sshd_enable to YES in /etc/rc.conf or use 'onestatus' instead of 'status'.
      # gather all enabled services
      cmd = inspec.command("#{service_ctl} -e")
      return nil if cmd.exit_status != 0

      # search for the service
      srv = /(^.*#{service_name}$)/.match(cmd.stdout)
      return nil if srv.nil? || srv[0].nil?

      enabled = true

      # check if the service is running
      # if the service is not available or not running, we always get an error code
      cmd = inspec.command("#{service_ctl} #{service_name} onestatus")
      running = cmd.exit_status == 0

      {
        name: service_name,
        description: nil,
        installed: true,
        running: running,
        enabled: enabled,
        type: "bsd-init",
      }
    end
  end

  class Runit < ServiceManager
    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "sv"
      super
    end

    # rubocop:disable Style/DoubleNegation
    def info(service_name)
      # get the status of runit service
      cmd = inspec.command("#{service_ctl} status #{service_name}")
      # return nil unless cmd.exit_status == 0 # NOTE(sr) why do we do this?

      installed = cmd.exit_status == 0
      running = installed && !!(cmd.stdout =~ /^run:/)
      enabled = installed && (running || !!(cmd.stdout =~ /normally up/) || !!(cmd.stdout =~ /want up/))

      {
        name: service_name,
        description: nil,
        installed: installed,
        running: running,
        enabled: enabled,
        type: "runit",
      }
    end
  end

  # MacOS / Darwin
  # new launctl on macos 10.10
  class LaunchCtl < ServiceManager
    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "launchctl"
      super
    end

    def info(service_name)
      # get the status of upstart service
      cmd = inspec.command("#{service_ctl} list")
      return nil if cmd.exit_status != 0

      # search for the service
      srv = /(^.*#{service_name}.*)/.match(cmd.stdout)
      return nil if srv.nil? || srv[0].nil?

      # extract values from service
      parsed_srv = /^(?<pid>[0-9-]+)\t(?<exit>[0-9]+)\t(?<name>\S*)$/.match(srv[0])
      enabled = !parsed_srv["name"].nil? # it's in the list

      # check if the service is running
      pid = parsed_srv["pid"]
      running = pid != "-"

      # extract service label
      srv = parsed_srv["name"] || service_name

      {
        name: srv,
        description: nil,
        installed: true,
        running: running,
        enabled: enabled,
        type: "darwin",
      }
    end
  end

  # Determine the service state from Windows
  # Uses Powershell to retrieve the information
  class WindowsSrv < ServiceManager
    # Determine service details
    # PS: Get-Service -Name 'dhcp'| Select-Object -Property Name, DisplayName, Status | ConvertTo-Json
    # {
    #     "Name":  "dhcp",
    #     "DisplayName":  "DHCP Client",
    #     "Status":  4
    # }
    #
    # Until StartMode is not added to Get-Service, we need to do a workaround
    # @see: https://connect.microsoft.com/PowerShell/feedback/details/424948/i-would-like-to-see-the-property-starttype-added-to-get-services
    # Also see: https://msdn.microsoft.com/en-us/library/aa384896(v=vs.85).aspx
    # Use the following powershell to determine the start mode
    # PS: Get-WmiObject -Class Win32_Service | Where-Object {$_.Name -eq $name -or $_.DisplayName -eq $name} | Select-Object -Prop
    # erty Name, StartMode, State, Status, StartName | ConvertTo-Json
    # {
    #     "Name":  "Dhcp",
    #     "StartMode":  "Auto",
    #     "State":  "Running",
    #     "Status":  "OK",
    #     "StartName":  "LocalSystem"
    # }
    #
    # Windows Services have the following status code:
    # @see: https://msdn.microsoft.com/en-us/library/windows/desktop/ms685996(v=vs.85).aspx
    # - 1: Stopped
    # - 2: Starting
    # - 3: Stopping
    # - 4: Running
    # - 5: Continue Pending
    # - 6: Pause Pending
    # - 7: Paused
    def info(service_name)
      cmd = inspec.command("New-Object -Type PSObject | Add-Member -MemberType NoteProperty -Name Service -Value (Get-Service -Name '#{service_name}'| Select-Object -Property Name, DisplayName, Status) -PassThru | Add-Member -MemberType NoteProperty -Name WMI -Value (Get-WmiObject -Class Win32_Service | Where-Object {$_.Name -eq '#{service_name}' -or $_.DisplayName -eq '#{service_name}'} | Select-Object -Property StartMode, StartName) -PassThru | ConvertTo-Json")

      # cannot rely on exit code for now, successful command returns exit code 1
      # return nil if cmd.exit_status != 0
      # try to parse json
      begin
        service = JSON.parse(cmd.stdout)
      rescue JSON::ParserError => _e
        return nil
      end

      # check that we got a response
      return nil if service.nil? || service["Service"].nil?

      {
        name: service["Service"]["Name"],
        description: service["Service"]["DisplayName"],
        installed: true,
        running: service_running?(service),
        enabled: service_enabled?(service),
        startmode: service["WMI"]["StartMode"],
        startname: service["WMI"]["StartName"],
        type: "windows",
      }
    end

    private

    # detect if service is enabled
    def service_enabled?(service)
      !service["WMI"].nil? &&
        !service["WMI"]["StartMode"].nil? &&
        (service["WMI"]["StartMode"] == "Auto" ||
        service["WMI"]["StartMode"] == "Manual")
    end

    # detect if service is running
    def service_running?(service)
      !service["Service"]["Status"].nil? && service["Service"]["Status"] == 4
    end
  end

  # Solaris services
  class Svcs < ServiceManager
    def initialize(service_name, service_ctl = nil)
      @service_ctl = service_ctl || "svcs"
      super
    end

    def info(service_name)
      # get the status of runit service
      cmd = inspec.command("#{service_ctl} -l #{service_name}")
      return nil if cmd.exit_status != 0

      params = SimpleConfig.new(
        cmd.stdout.chomp,
        assignment_regex: /^(\w+)\s*(.*)$/,
        multiple_values: false
      ).params

      installed = cmd.exit_status == 0
      running = installed && (params["state"] == "online")
      enabled = installed && (params["enabled"] == "true")

      {
        name: service_name,
        description: params["name"],
        installed: installed,
        running: running,
        enabled: enabled,
        type: "svcs",
      }
    end
  end

  # specific resources for specific service managers

  class SystemdService < Service
    name "systemd_service"
    supports platform: "unix"
    desc "Use the systemd_service InSpec audit resource to test if the named service (controlled by systemd) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe systemd_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard systemctl path
      describe systemd_service('service_name', '/path/to/systemctl') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      Systemd.new(inspec, service_ctl)
    end
  end

  class UpstartService < Service
    name "upstart_service"
    supports platform: "unix"
    desc "Use the upstart_service InSpec audit resource to test if the named service (controlled by upstart) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe upstart_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard initctl path
      describe upstart_service('service_name', '/path/to/initctl') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      Upstart.new(inspec, service_ctl)
    end
  end

  class SysVService < Service
    name "sysv_service"
    supports platform: "unix"
    desc "Use the sysv_service InSpec audit resource to test if the named service (controlled by SysV) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe sysv_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard service path
      describe sysv_service('service_name', '/path/to/service') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      SysV.new(inspec, service_ctl)
    end
  end

  class BSDService < Service
    name "bsd_service"
    supports platform: "unix"
    desc "Use the bsd_service InSpec audit resource to test if the named service (controlled by BSD init) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe bsd_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard service path
      describe bsd_service('service_name', '/path/to/service') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      BSDInit.new(inspec, service_ctl)
    end
  end

  class LaunchdService < Service
    name "launchd_service"
    supports platform: "unix"
    desc "Use the launchd_service InSpec audit resource to test if the named service (controlled by launchd) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe launchd_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard launchctl path
      describe launchd_service('service_name', '/path/to/launchctl') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      LaunchCtl.new(inspec, service_ctl)
    end
  end

  class RunitService < Service
    name "runit_service"
    supports platform: "unix"
    desc "Use the runit_service InSpec audit resource to test if the named service (controlled by runit) is installed, running and/or enabled."
    example <<~EXAMPLE
      # to override service mgmt auto-detection
      describe runit_service('service_name') do
        it { should be_installed }
        it { should be_enabled }
        it { should be_running }
      end

      # to set a non-standard sv path
      describe runit_service('service_name', '/path/to/sv') do
        it { should be_running }
      end
    EXAMPLE

    def select_service_mgmt
      Runit.new(inspec, service_ctl)
    end
  end
end
