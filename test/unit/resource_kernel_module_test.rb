# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::KernelModule' do
  it 'verify kernel_module parsing' do
    resource = loadResource('kernel_module', 'bridge')
    _(resource.loaded?).must_equal true
  end

  it 'verify kernel_module parsing' do
    resource = loadResource('kernel_module', 'bridges')
    _(resource.loaded?).must_equal false
  end

  it 'verify kernel_module parsing' do
    resource = loadResource('kernel_module', 'dhcp')
    _(resource.loaded?).must_equal false
  end
end
