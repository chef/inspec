# encoding: utf-8

require 'yaml'

module Inspec::Reporters
  class Yaml < Base
    def render
      output(Inspec::Reporters::Json.new({ run_data: run_data }).report.to_yaml, false)
    end
  end
end
