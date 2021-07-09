lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "inspec/version"

Gem::Specification.new do |spec|
  spec.name          = "inspec-core"
  spec.version       = Inspec::VERSION
  spec.authors       = ["Chef InSpec Team"]
  spec.email         = ["inspec@chef.io"]
  spec.summary       = "Infrastructure and compliance testing. Core library."
  spec.description   = "InSpec provides a framework for creating end-to-end infrastructure tests. You can use it for integration or even compliance testing. Create fully portable test profiles and use them in your workflow to ensure stability and security. Integrate InSpec in your change lifecycle for local testing, CI/CD, and deployment verification. This has local support only. See the `inspec` gem for full support."
  spec.homepage      = "https://github.com/inspec/inspec"
  spec.license       = "Apache-2.0"
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.5"

  # the gemfile and gemspec are necessary for appbundler so don't remove it
  spec.files =
    Dir.glob("{{lib,etc}/**/*,LICENSE,Gemfile,inspec-core.gemspec}")
      .grep_v(%r{(?<!inspec-init/templates/profiles/)(aws|azure|gcp)})
      .grep_v(%r{lib/plugins/.*/test/})
      .reject { |f| File.directory?(f) }

  # Implementation dependencies
  spec.add_dependency "chef-telemetry",     "~> 1.0", ">= 1.0.8" # 1.0.8+ removes the http dep
  spec.add_dependency "license-acceptance", ">= 0.2.13", "< 3.0"
  spec.add_dependency "thor",               ">= 0.20", "< 2.0"
  spec.add_dependency "method_source",      ">= 0.8", "< 2.0"
  spec.add_dependency "rubyzip",            ">= 1.2.2", "< 3.0"
  spec.add_dependency "rspec",              ">= 3.9", "< 3.11"
  spec.add_dependency "rspec-its",          "~> 1.2"
  spec.add_dependency "pry",                "~> 0.13"
  spec.add_dependency "hashie",             ">= 3.4", "< 5.0"
  spec.add_dependency "mixlib-log",         "~> 3.0"
  spec.add_dependency "sslshake",           "~> 1.2"
  spec.add_dependency "parallel",           "~> 1.9"
  spec.add_dependency "faraday",            ">= 0.9.0", "< 1.5"
  spec.add_dependency "faraday_middleware", "~> 1.0"
  spec.add_dependency "tty-table",          "~> 0.10"
  spec.add_dependency "tty-prompt",         "~> 0.17"
  spec.add_dependency "tomlrb",             ">= 1.2", "< 2.1"
  spec.add_dependency "addressable",        "~> 2.4"
  spec.add_dependency "parslet",            ">= 1.5", "< 3.0" # Pinned < 2.0, see #5389
  spec.add_dependency "semverse",           "~> 3.0"
  spec.add_dependency "multipart-post",     "~> 2.0"

  spec.add_dependency "train-core", "~> 3.0"
end
