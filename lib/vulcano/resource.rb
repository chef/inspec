# encoding: utf-8
# copyright: 2015, Vulcano Security GmbH
# license: All rights reserved
require 'vulcano/plugins'

module Vulcano
  class Resource
    def self.registry
      @registry ||= {}
    end
  end

  def self.resource(version)
    if version != 1
      fail 'Only resource version 1 is supported!'
    end
    Vulcano::Plugins::Resource
  end
end

require 'resources/apache_conf'
require 'resources/audit_policy'
require 'resources/auditd_conf'
require 'resources/auditd_rules'
require 'resources/bond'
require 'resources/command'
require 'resources/directory'
require 'resources/etc_group'
require 'resources/file'
require 'resources/group_policy'
require 'resources/inetd_conf'
require 'resources/limits_conf'
require 'resources/login_def'
require 'resources/mysql'
require 'resources/mysql_conf'
require 'resources/mysql_session'
require 'resources/ntp_conf'
require 'resources/os_env'
require 'resources/parse_config'
require 'resources/passwd'
require 'resources/postgres'
require 'resources/postgres_conf'
require 'resources/postgres_session'
require 'resources/processes'
require 'resources/registry_key'
require 'resources/security_policy'
require 'resources/ssh_conf'
require 'resources/yum'
