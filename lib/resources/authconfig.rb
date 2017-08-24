# encoding: utf-8
# author: Matthew Dromazos

require 'utils/SimpleConfig'
require 'utils/parser'
require 'pry'
require 'parslet'

module Inspec::Resources
  class AuthConfig < Inspec.resource(1)
    name 'authconfig'
    desc 'Use the `authconfig` InSpec audit resource to test the properties set in an authconfig file.
          The `authconfig` defines values that are used to track whether or not authentication mechanisms are enabled.'
    example "
    describe authconfig do
      its ('USESSSD') { should eq 'yes' }
    end

    describe authconfig do
      it { should be_smartcard_authen_enabled }
    end

    describe authconfig do
      its ( 'smartcard_removal_action' ) { should eq 'Ignore' }
    end
    "

    attr_reader :params

    def initialize(host_path = nil)
      return skip_resource 'The `authconfig` resource is not supported on your OS.' unless inspec.os.linux? || inspec.os.windows?
      @conf_path = host_path || '/etc/sysconfig/authconfig'
      @content = nil
      @params = nil
      @modules = nil
      read_content
    end

    def installed?
      inspec.package('authconfig').installed?
    end

    def method_missing(name)
      @params[name.to_s]
    end

    def smartcard_authen_enabled?
      return 'The `authconfig` resource is not installed on your machine.' unless installed?
      result = authconfig_command("authconfig --test | grep -i \"smartcard for login is\" | awk '{ print $NF }'")
      return result unless !result.match(/^Error.+/)
      result == 'enabled'
    end

    def smartcard_removal_action
      return 'The `authconfig` resource is not installed on your machine.' unless installed?
      authconfig_command("authconfig --test | grep -i 'smartcard removal action' | awk \'{ print $NF }\'")[1..-3]
    end

    private

    def read_content
      @content = ''
      @params = {}
      @modules = {}
      @content = read_file(@conf_path)
      @modules = read_modules(authconfig_command('authconfig --test'))
      @params = read_params(@content)
    end

    def read_params(content)
      # parse the file
      conf = SimpleConfig.new(
        content,
      )
      conf.params
    end

    def read_modules(content)
      binding.pry
      # parse the file
      conf = SimpleConfig.new(
        content,
        assignment_regex: /^\S([^=]*?)\s*is\s*(.*?)\s*$/,
      )
      conf.params
    end

    def read_file(conf_path = @conf_path)
      file = inspec.file(conf_path)
      if !file.file?
        return skip_resource "Can't find file. \"#{@conf_path}\""
      end

      raw_conf = file.content
      if raw_conf.empty? && !file.empty?
        return skip_resource("File is empty.\"#{@conf_path}\"")
      end
      inspec.file(conf_path).content
    end

    def authconfig_command(command)
      result = inspec.command(command)
      if result.stderr != ''
        return "Error on command #{command}: #{result.stderr}"
      end
      result.stdout
    end
  end
  class Mini < Parslet::Parser
    rule(:nonSpace) { match('\S').repeat(1) }
    rule(:space) { match('\s').repeat(1) }

    rule(:wordAndSpace ) { nonSpace || space }
    rule(:is) { match('\s') >> str('is') >> match('\s') }
    rule(:equals) { match('\s') >> str('=') >> match('\s') }
    rule(:is_expression) { wordAndSpace.as(:left) >> is.as(:is) >> wordAndSpace.as(:right) }
    rule(:equals_expression) { wordAndSpace.as(:left) >> is.as(:is) >> wordAndSpace.as(:right) }
    root :expression
  end
end
