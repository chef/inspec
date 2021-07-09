require "inspec/resources/opa"

module Inspec::Resources
  class OpaCli < Opa
    name "opa_cli"
    supports platform: "unix"
    supports platform: "windows"

    attr_reader :allow

    def initialize(opts = {})
      @opa_executable_path = opts[:opa_executable_path] || "opa" #if this path is not provided then we will assume that it's been set in the ENV PATH
      @policy = opts[:policy] || nil
      @data = opts[:data] || nil
      @query = opts[:query] || nil
      fail_resource "OPA policy, data and query are mandatory." if @policy.nil? || @data.nil? || @query.nil?
      @content = load_result
      super(@content)
    end

    def allow
      @content["result"][0]["expressions"][0]["value"] if @content["result"][0]["expressions"][0]["text"].include?("allow")
    end

    def to_s
      "OPA cli"
    end

    private

    def load_result
      raise Inspec::Exceptions::ResourceFailed, "#{resource_exception_message}" if resource_failed?

      result = inspec.command("#{@opa_executable_path} eval -i '#{@data}' -d '#{@policy}' '#{@query}'")
      if result.exit_status == 0
        result.stdout.gsub("\n", "")
      else
        error = result.stdout + "\n" + result.stderr
        raise Inspec::Exceptions::ResourceFailed, "Error while executing OPA query: #{error}"
      end
    end
  end
end
