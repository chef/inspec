# encoding: utf-8

require 'helper'

describe 'Vulcano::Backend' do

  it 'should have a populated registry' do
    reg = Vulcano::Backend.registry
    reg.must_be_kind_of Hash
    reg.keys.must_include 'local'
    reg.keys.must_include 'mock'
    reg.keys.must_include 'specinfra'
  end


  describe 'target config helper' do
    it 'configures resolves target' do
      org = {
        'target' => 'ssh://user:pass@host.com:123',
      }
      res = Vulcano::Backend.target_config(org)
      res['backend'].must_equal 'ssh'
      res['host'].must_equal 'host.com'
      res['user'].must_equal 'user'
      res['password'].must_equal 'pass'
      res['port'].must_equal 123
      res['target'].must_equal org['target']
      org.keys.must_equal ['target']
    end

    it 'resolves a target while keeping existing fields' do
      org = {
        'target' => 'ssh://user:pass@host.com:123',
        'backend' => rand,
        'host' => rand,
        'user' => rand,
        'password' => rand,
        'port' => rand,
      }
      res = Vulcano::Backend.target_config(org)
      res.must_equal org
    end

    it 'keeps the configuration when incorrect target is supplied' do
      org = {
        'target' => 'wrong',
      }
      res = Vulcano::Backend.target_config(org)
      res['backend'].must_be_nil
      res['host'].must_be_nil
      res['user'].must_be_nil
      res['password'].must_be_nil
      res['port'].must_be_nil
      res['target'].must_equal org['target']
    end
  end

  describe 'helper method for creating backends' do
    it 'creates v1 backends by default' do
      Vulcano.backend.must_equal Vulcano::Plugins::Backend
    end

    it 'creates v1 backends' do
      Vulcano.backend(1).must_equal Vulcano::Plugins::Backend
    end
  end

end
