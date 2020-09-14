require "forwardable"
require "singleton"
require "train"

require_relative "status"
require_relative "activator"

module Inspec::Plugin::V2
  class Registry
    include Singleton
    extend Forwardable

    attr_reader :registry
    def_delegator :registry, :each
    def_delegator :registry, :[]
    def_delegator :registry, :key?, :known_plugin?
    def_delegator :registry, :keys, :plugin_names
    def_delegator :registry, :values, :plugin_statuses
    def_delegator :registry, :select

    def initialize
      @registry = {}
    end

    def any_load_failures?
      !plugin_statuses.select(&:load_exception).empty?
    end

    def loaded_plugin?(name)
      # HACK: Status is normally the source of truth for loadedness, unless it is a train plugin; then the Train::Registry is the source of truth.
      # Also, InSpec registry is keyed on Symbols; Train is keyed on Strings.
      return registry.dig(name.to_sym, :loaded) unless name.to_s.start_with?("train-")

      Train::Plugins.registry.key?(name.to_s.sub(/^train-/, ""))
    end

    def loaded_count
      loaded_plugin_names.count
    end

    def known_count
      registry.values.count
    end

    def loaded_plugin_names
      registry.keys.select { |name| loaded_plugin?(name) }
    end

    def path_based_plugin?(name)
      known_plugin?(name.to_sym) && registry[name.to_sym].installation_type == :path
    end

    def profile_bundled_plugin?(name)
      return unless known_plugin?(name.to_sym)

      registry[name.to_sym].installation_type == :profile_bundled || name.start_with?("profile")
    end

    def find_status_by_class(klass)
      registry.values.detect { |status| status.plugin_class == klass }
    end

    # Finds Activators matching criteria (all optional) you specify as a Hash.
    # @param [Symbol] plugin_name Restricts the search to the given plugin
    # @param [Symbol] plugin_type Restricts the search to the given plugin type
    # @param [Symbol] activator_name Name of the activator
    # @param [Class] implementation_class Implementation class returned by an already-actived plugin type
    # @returns [Array] Possibly empty array of Activators
    def find_activators(filters = {})
      plugin_statuses.map(&:activators).flatten.select do |act|
        %i{plugin_name plugin_type activator_name implementation_class}.all? do |criteria|
          !filters.key?(criteria) || act[criteria] == filters[criteria]
        end
      end
    end

    # Convenience method for when you expect exactly one
    def find_activator(filters = {})
      matched_plugins = find_activators(filters)
      if matched_plugins.count > 1
        raise Inspec::Plugin::V2::LoadError, "Plugin hooks search returned multiple results for filter #{filters.inspect} - use more filters, or use find_activators (plural)"
      elsif matched_plugins.empty?
        raise Inspec::Plugin::V2::LoadError, "Plugin hooks search returned zero results for filter #{filters.inspect}"
      end

      matched_plugins.first
    end

    def register(name, status)
      if known_plugin? name
        Inspec::Log.debug "PluginLoader: refusing to re-register plugin '#{name}': an existing plugin with that name was loaded via #{registry[name].installation_type}-loading from #{registry[name].entry_point}"
      else
        registry[name.to_sym] = status
      end
    end

    alias []= register

    # Provided for test support. Purges the registry.
    def __reset
      @registry.clear
    end
  end
end
