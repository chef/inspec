# encoding: utf-8

require 'helper'
require 'vulcano/resource'

describe 'Vulcano::Resources::LimitsConf' do
  describe 'limits_conf' do
    let(:resource) { loadResource('limits_conf') }

    it 'verify limits.conf config parsing' do
      _(resource.send('*')).must_equal [['soft', 'core', '0'], ['hard', 'rss', '10000']]
      _(resource.send('ftp')).must_equal [["hard", "nproc", "0"]]
    end
  end
end
