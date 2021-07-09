module InspecPlugins
  module TestFixture

    class Plugin < Inspec.plugin(2)
      plugin_name :'inspec-test-fixture'

      mock_plugin_type :'inspec-test-fixture' do
        require 'mock_plugin'
        InspecPlugins::TestFixture
      end
    end
  end
end