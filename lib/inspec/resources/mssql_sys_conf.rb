require "inspec/resources/mssql_session"

module Inspec::Resources
  class MssqlSysConf < Inspec.resource(1)
    name "mssql_sys_conf"
    supports platform: "windows"
    supports platform: "debian"
    supports platform: "redhat"
    supports platform: "suse"

    desc "Use the mssql_sys_conf InSpec audit resource to test the database system configurations for Mssql DB"
    example <<~EXAMPLE
      describe mssql_sys_conf("clr_enabled", user: 'USER', password: 'PASSWORD') do
        its("value_in_use") { should cmp "0" }
        its("value_configured") { should cmp "0" }
      end
    EXAMPLE

    attr_reader :mssql_session, :sql_query

    def initialize(conf_param_name, opts = {})
      opts[:username] ||= "SA"
      @mssql_session = inspec.mssql_session(opts)
      setting = conf_param_name.to_s.gsub("_", " ").split.map(&:capitalize).join(" ")
      determine_system_configurations(setting)
    end

    def value_in_use
      sql_query.row(0).column("value_in_use").value
    end

    def value_configured
      sql_query.row(0).column("value_configured").value
    end

    def to_s
      "MsSql DB Configuration"
    end

    private

    def determine_system_configurations(setting)
      @sql_query = mssql_session.query("SELECT name, CAST(value as int) as value_configured, CAST(value_in_use as int) as value_in_use FROM sys.configurations WHERE name = '#{setting}'")
    rescue => e
      raise Inspec::Exceptions::ResourceFailed, "Errors fetching database system configurations for Mssql database: #{e}"
    end
  end
end