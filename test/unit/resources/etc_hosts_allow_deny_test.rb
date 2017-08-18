# encoding: utf-8
# author: Matthew Dromazos

require 'helper'
require 'inspec/resource'

describe 'Inspec::Resources::EtcHostsAllow' do
  describe 'EtcHostsAllow Paramaters' do
    resource = load_resource('etc_hosts_allow')
    it 'Verify etc_hosts_allow filtering by `daemon`'  do
      entries = resource.where { daemon == 'ALL' }
      _(entries.client_list).must_include ['127.0.0.1', '[::1]']
      _(entries.options).must_equal [[]]
    end
    it 'Verify etc_hosts_allow filtering by `client_list`'  do
      entries = resource.where { client_list == ['127.0.1.154',  '[:fff:fAb0::]'] }
      _(entries.daemon).must_equal ['vsftpd', 'sshd']
      _(entries.options).must_include ['deny', '/etc/bin/']
    end
    it 'Verify etc_hosts_allow filtering by `options`'  do
      entries = resource.where { options == ['deny', '/etc/bin/'] }
      _(entries.daemon).must_equal ['vsftpd', 'sshd']
      _(entries.client_list).must_include ['127.0.1.154',  '[:fff:fAb0::]']
    end
  end
end

describe 'Inspec::Resources::EtcHostsDeny' do
  describe 'EtcHostsDeny Paramaters' do
    resource = load_resource('etc_hosts_deny')
    it 'Verify etc_hosts_deny filtering by `daemon`'  do
      entries = resource.where { daemon == 'ALL' }
      _(entries.client_list).must_include ['127.0.0.1', '[::1]']
      _(entries.options).must_equal [[]]
    end
    it 'Verify etc_hosts_deny filtering by `client_list`'  do
      entries = resource.where { client_list == ['127.0.1.154',  '[:fff:fAb0::]'] }
      _(entries.daemon).must_equal ['vsftpd', 'sshd']
      _(entries.options).must_include ['deny', '/etc/bin/']
    end
    it 'Verify etc_hosts_deny filtering by `options`'  do
      entries = resource.where { options == ['deny', '/etc/bin/'] }
      _(entries.daemon).must_equal ['vsftpd', 'sshd']
      _(entries.client_list).must_include ['127.0.1.154',  '[:fff:fAb0::]']
    end
  end
end
