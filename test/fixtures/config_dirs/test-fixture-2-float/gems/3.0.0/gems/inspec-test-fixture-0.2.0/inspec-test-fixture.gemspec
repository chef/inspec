lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "inspec-test-fixture/version"

Gem::Specification.new do |spec|
  spec.name          = "inspec-test-fixture"
  spec.version       = "0.2.0"
  spec.authors       = ["InSpec Engineering Team"]
  spec.email         = ["hello@chef.io"]

  spec.summary       = %q{A simple test plugin gem for InSpec}
  spec.description   = %q{This gem is used to test the gem search and install capabilities of InSpec's plugin V2 system.  It is not a good example or starting point for plugin development.}
  spec.homepage      = "https://github.com/inspec/inspec"

  spec.files         = [
    "inspec-test-fixture.gemspec",
    "lib/inspec-test-fixture.rb",
    "lib/inspec-test-fixture/plugin.rb",
    "lib/inspec-test-fixture/mock_plugin.rb",
    "lib/inspec-test-fixture/version.rb",
  ]
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "ordinal_array", "~> 0.2.0"
end
