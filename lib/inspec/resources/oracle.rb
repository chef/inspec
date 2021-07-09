require "inspec/resources/powershell"

module Inspec::Resources
  class Oracle < Inspec.resource(1)
    name "oracle"
    supports platform: "unix"
    supports platform: "windows"

    desc "The 'oracle' resource is a helper for the 'oracledb_listener_conf'"

    attr_reader :conf_path

    def initialize
      case inspec.os[:family]
      when "debian", "redhat", "linux", "suse"
        determine_conf_dir_and_path_in_linux
      when "windows"
        determine_conf_dir_and_path_in_windows
      end
    end

    def to_s
      "OracleDB"
    end

    private

    def determine_conf_dir_and_path_in_linux
      oracle_home = inspec.os_env("ORACLE_HOME").content

      if oracle_home.nil? || oracle_home.empty?
        warn "$ORACLE_HOME env value not set in the system"
        nil
      else
        conf_path = "#{oracle_home}/network/admin/listener.ora"
        if !inspec.file(conf_path).exist?
          warn "No oracle listener settings found in $ORACLE_HOME/network/admin directory"
          nil
        else
          @conf_path = conf_path
        end
      end
    rescue => e
      fail_resource "Errors reading listener settings: #{e}"
    end

    def determine_conf_dir_and_path_in_windows
      oracle_home = inspec.os_env("ORACLE_HOME").content

      if oracle_home.nil? || oracle_home.empty?
        warn "ORACLE_HOME env value not set in the system"
        nil
      else
        conf_path = "#{oracle_home}\\network\\admin\\listener.ora"
        if !inspec.file(conf_path).exist?
          warn "No oracle listener settings found in ORACLE_HOME\\network\\admin directory"
          nil
        else
          @conf_path = conf_path
        end
      end
    rescue => e
      fail_resource "Errors reading listener settings: #{e}"
    end
  end
end
