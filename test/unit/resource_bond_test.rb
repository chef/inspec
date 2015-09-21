# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::Bond' do

  describe 'parse bond config' do

    let(:resource) { loadResource('bond', 'bond0') }

    it 'bond must be available' do
      resource.exist?.must_equal true
    end

    it 'eth0 is part of bond' do
      _(resource.has_interface?('eth0')).must_equal true
      _(resource.has_interface?('eth1')).must_equal false
      _(resource.has_interface?('eth2')).must_equal true
    end

    it 'get all interfaces' do
      _(resource.interfaces).must_equal %w{eth0 eth2}
    end

    it 'get proc content' do
      _(resource.content).wont_equal nil
      _(resource.content).wont_equal ''
    end
  end
end
