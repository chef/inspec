# stub: train-test-fixture 0.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "train-test-fixture".freeze
  s.version = "0.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["InSpec core engineering team".freeze]
  s.date = "2018-09-26"
  s.description = "Train plugin used in testing Train's plugin loader and InSpec's plugin manager.\nThis plugin does things that a normal plugin should not.  Do not use it as an\nexample or as a starting point for plugin of your own.  For that, please see\nhttps://github.com/inspec/train/tree/master/examples/plugins\n".freeze
  s.email = ["hello@chef.io".freeze]
  s.homepage = "https://github.com/inspec/train".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.rubygems_version = "2.6.13".freeze
  s.summary = "Test train plugin. Not intended for use as an example.".freeze

  s.installed_by_version = "2.6.13" if s.respond_to? :installed_by_version
end
