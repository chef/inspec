# chrony_conf

require "inspec/utils/simpleconfig"
require "inspec/utils/file_reader"

module Inspec::Resources
  class ChronyConf < Inspec.resource(1)
    name "chrony_conf"
    supports platform: "unix"
    desc "Use the chrony_conf InSpec audit resource to test the synchronization settings defined in the chrony.conf file. This file is typically located at /etc/chrony.conf."
    example <<~EXAMPLE
      describe chrony_conf do
        its('server') { should_not cmp nil }
        its('restrict') { should include '-4 default kod notrap nomodify nopeer noquery' }
        its('pool') { should include 'pool.ntp.org iburst' }
        its('driftfile') { should cmp '/var/lib/ntp/drift' }
        its('allow') { should cmp nil }
        its('keyfile') { should cmp '/etc/chrony.keys' }
      end
    EXAMPLE

    include FileReader

    def initialize(path = nil)
      @conf_path = path || "/etc/chrony.conf"
      @content = read_file_content(@conf_path)
    end

    def method_missing(name)
      param = read_params[name.to_s]
      # extract first value if we have only one value in array
      return param[0] if param.is_a?(Array) && (param.length == 1)

      param
    end

    def to_s
      "chrony.conf"
    end

    private

    def read_params
      return @params if defined?(@params)

      # parse the file
      conf = SimpleConfig.new(
        @content,
        assignment_regex: /^\s*(\S+)\s+(.*)\s*$/,
        multiple_values: true
      )
      @params = conf.params
    end
  end
end
