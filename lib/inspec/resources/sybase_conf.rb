require "inspec/resources/sybase_session"

module Inspec::Resources
  class SybaseConf < Inspec.resource(1)
    name "sybase_conf"
    supports platform: "unix"
    # supports platform: "windows" # TODO
    desc "Use the sybase_conf InSpec resource to test Sybase config settings"
    example <<~EXAMPLE
      describe sybase_conf("max memory", password: 'password', server: 'SYBASE') do
        its("run_value") { should cmp 180224 }
      end
    EXAMPLE

    attr_reader :conf_param, :sql_query
    def initialize(conf_param_name, opts = {})
      @conf_param = conf_param_name
      opts[:username] ||= "sa"
      opts[:database] ||= "master"
      sql_session = inspec.sybase_session(opts)
      @sql_query = sql_session.query("sp_configure \"#{conf_param}\"")
    end

    def run_value
      sql_query.row(0).column("Run Value").value
    end

    def config_value
      sql_query.row(0).column("Config Value").value
    end

    def to_s
      "Sybase Conf #{conf_param}"
    end

  end
end
