require "inspec/resources/json"

module Inspec::Resources
  class Opa < JsonConfig
    name "opa"
    supports platform: "unix"
    supports platform: "windows"

    attr_reader :result
    def initialize(content)
      @content = content
      super({content: @content})
    end

    private

    def parse(content)
      @content = YAML.load(content)
    rescue => e
      raise Inspec::Exceptions::ResourceFailed, "Unable to parse OPA query output: #{e.message}"
    end
  end
end
