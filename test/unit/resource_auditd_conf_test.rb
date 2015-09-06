# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::AuditDaemonConf' do
  describe 'audit_daemon_conf' do
    let(:resource) { loadResource('audit_daemon_conf') }

    it 'check audit daemon config parsing' do
      _(resource.space_left_action).must_equal 'SYSLOG'
      _(resource.action_mail_acct).must_equal 'root'
      _(resource.admin_space_left_action).must_equal 'SUSPEND'
      _(resource.tcp_listen_queue).must_equal '5'
    end
  end
end
