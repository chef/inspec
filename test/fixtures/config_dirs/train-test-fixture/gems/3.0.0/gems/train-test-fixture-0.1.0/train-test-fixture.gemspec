lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "train-test-fixture"
  spec.version       = "0.1.0"
  spec.authors       = ["InSpec core engineering team"]
  spec.email         = ["hello@chef.io"]
  spec.license       = "Apache-2.0"

  spec.summary       = %q{Test train plugin. Not intended for use as an example.}
  spec.description   = <<~EOD
    Train plugin used in testing Train's plugin loader and InSpec's plugin manager.
    This plugin does things that a normal plugin should not.  Do not use it as an
    example or as a starting point for plugin of your own.  For that, please see
    https://github.com/inspec/train/tree/master/examples/plugins
  EOD
  spec.homepage      = "https://github.com/inspec/train"

  spec.files         = %w{
    README.md
    LICENSE
    lib/train-test-fixture.rb
    lib/train-test-fixture/version.rb
    lib/train-test-fixture/transport.rb
    lib/train-test-fixture/connection.rb
    lib/train-test-fixture/platform.rb
    train-test-fixture.gemspec
  }
  spec.executables   = []
  spec.require_paths = ["lib"]

  # No deps
end
