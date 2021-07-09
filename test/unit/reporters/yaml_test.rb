require "helper"
require "inspec/reporters"

describe Inspec::Reporters::Yaml do
  WINDOWS = RUBY_PLATFORM =~ /windows|mswin|msys|mingw|cygwin/
  RUBY3_PLUS = Gem.ruby_version >= Gem::Version.new("3.0")

  let(:report) do
    data = YAML.load_file("test/fixtures/reporters/run_data.yml")
    Inspec::Reporters::Yaml.new({ run_data: data })
  end

  describe "#render" do
    it "confirm render output" do
      if WINDOWS && RUBY3_PLUS
        # Under Windows on Ruby 3+, empty scalar values are generated without a trailing space
        # this affects the title: and desc: fields
        output = File.read("test/fixtures/reporters/yaml_output_windows_ruby3plus")
      else
        output = File.read("test/fixtures/reporters/yaml_output")
      end
      report.render
      _(report.rendered_output).must_equal output
    end
  end
end
