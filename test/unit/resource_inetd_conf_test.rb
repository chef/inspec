# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::InetdConf' do
  describe 'inetd_config' do
    let(:resource) { loadResource('inetd_config') }

    it 'verify limits.conf config parsing' do
      _(resource.send('shell')).must_equal nil
      _(resource.send('login')).must_equal nil
      _(resource.send('ftp')).must_equal %w{stream tcp nowait root /usr/sbin/in.ftpd in.ftpd}
    end
  end
end
