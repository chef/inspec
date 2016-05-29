# encoding: utf-8
# author: Christoph Hartmann
# author: Dominik Richter

require 'uri'
require 'inspec/fetcher'
require 'fetchers/url'

# InSpec Target Helper for Supermarket
module Supermarket
  class Fetcher < Fetchers::Url
    name 'supermarket'
    priority 500

    def self.resolve(target, opts = {})
      uri = URI(target)
      return nil unless uri.scheme == 'supermarket'
      Supermarket::Helper.parse_host(target)
      return nil unless Supermarket::API.exist?(target)
      tool_info = Supermarket::API.find(target)
      super(tool_info['tool_source_url'], opts)
    rescue URI::Error => _e
      nil
    end

    def to_s
      'Chef Compliance Profile Loader'
    end
  end
end
