lib = File.expand_path("../../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'inspec-test-fixture/version'
require 'inspec-test-fixture/plugin'
