require "inspec/resources/oracledb_session"

module Inspec::Resources
  class OracledbConf < Inspec.resource(1)
    name "oracledb_conf"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the oracledb_conf InSpec audit resource to test the database settings for Oracle DB"
    example <<~EXAMPLE
      describe oracledb_conf(user: 'USER', password: 'PASSWORD') do
        its("audit_sys_operations") { should cmp "true" }
        its("sql92_security") { should cmp "true" }
      end
    EXAMPLE

    attr_reader :oracledb_session

    def initialize(opts = {})
      @oracledb_session = inspec.oracledb_session(opts)
    end

    def method_missing(name)
      setting = name.to_s.upcase
      determine_database_setting(setting)
    end

    def to_s
      "Oracle DB Configuration"
    end

    private

    def determine_database_setting(setting)
      sql_query = oracledb_session.query("SELECT UPPER(VALUE) AS UPPER_VALUE FROM V$SYSTEM_PARAMETER WHERE UPPER(NAME) = '#{setting}'")
      sql_query.row(0).column("UPPER_VALUE").value
    rescue => e
      raise Inspec::Exceptions::ResourceFailed, "Errors fetching database settings for Oracle database: #{e}"
    end
  end
end
