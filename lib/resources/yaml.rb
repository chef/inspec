# encoding: utf-8
# author: Christoph Hartmann
# author: Dominik Richter

require 'yaml'

# Parses a yaml document
# Usage:
# describe yaml('.kitchen.yaml') do
#   its('driver.name') { should eq('vagrant') }
# end
module Inspec::Resources
  class YamlConfig < JsonConfig
    name 'yaml'
    desc 'Use the yaml InSpec audit resource to test configuration data in a YAML file.'
    example "
      describe yaml('config.yaml') do
        its(['driver', 'name']) { should eq 'vagrant' }
      end

      describe yaml({ command: 'retrieve_data.py --yaml' }) do
        its('state') { should eq 'open' }
      end

      describe yaml({ content: \"key1: value1\nkey2: value2\" }) do
        its('key2') { should cmp 'value2' }
      end
    "

    # override file load and parse hash from yaml
    def parse(content)
      YAML.load(content)
    rescue => e
      raise Inspec::Exceptions::ResourceFailed, "Unable to parse YAML: #{e.message}"
    end

    # used by JsonConfig to build up a full to_s method
    # based on whether a file path, content, or command was supplied.
    def resource_base_name
      'YAML'
    end
  end
end
