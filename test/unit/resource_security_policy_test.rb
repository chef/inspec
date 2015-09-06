# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::SecurityPolicy' do
  describe 'security_policy' do
    let(:resource) { loadResource('security_policy') }

    it 'verify processes resource' do
      _(resource.MaximumPasswordAge).must_equal 42
      _(resource.SeUndockPrivilege).must_equal '*S-1-5-32-544'
      _(resource.send('MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SecurityLevel')).must_equal '4,0'
      _(resource.SeRemoteInteractiveLogonRight).must_equal '*S-1-5-32-544,*S-1-5-32-555'
    end
  end
end
