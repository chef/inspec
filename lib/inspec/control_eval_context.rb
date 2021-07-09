require "inspec/dsl"
require "inspec/dsl_shared"
require "rspec/core/dsl"

module Inspec
  #
  # ControlEvalContext constructs an anonymous class that control
  # files will be instance_exec'd against.
  #
  # The anonymous class includes the given passed resource_dsl as well
  # as the basic DSL of the control files (describe, control, title,
  # etc).
  #
  class ControlEvalContext
    include Inspec::DSL
    include Inspec::DSL::RequireOverride

    attr_accessor :skip_file
    attr_accessor :profile_context
    attr_accessor :resources_dsl

    def initialize(profile_context, resources_dsl, backend, conf, dependencies, require_loader, skip_only_if_eval)
      @profile_context = profile_context
      @resources_dsl = resources_dsl
      @backend = backend
      @conf = conf
      @dependencies = dependencies
      @require_loader = require_loader
      @skip_file_message = nil
      @skip_file = false
      @skip_only_if_eval = skip_only_if_eval

      extend resources_dsl # TODO: remove? push to method_missing?
    end

    alias profile_context_owner profile_context

    def profile_id
      profile_context.profile_id
    end

    def to_s
      "Control Evaluation Context (#{profile_name})"
    end

    def title(arg)
      profile_context_owner.set_header(:title, arg)
    end

    def profile_name
      profile_id
    end

    def control(id, opts = {}, &block)
      opts[:skip_only_if_eval] = @skip_only_if_eval
      tag_ids = control_tags(&block)
      if (controls_list_empty? && tags_list_empty?) || control_exist_in_controls_list?(id) || tag_exist_in_control_tags?(tag_ids)
        register_control(Inspec::Rule.new(id, profile_id, resources_dsl, opts, &block))
      end
    end

    alias rule control

    def control_tags(&block)
      tag_source = block.source.split("\n").select { |src| src.split.first.eql?("tag") }
      tag_source = tag_source.map { |src| src.sub("tag", "").strip }.map { |src| src.split(",").map { |final_src| final_src.gsub(/([^:]*):/, "") } }.flatten
      output = tag_source.map { |src| src.gsub(/\[|\]/, "") }.map { |src| instance_eval(src) }
      output.compact.uniq
    rescue => e
      raise "Unable to fetch control tags: #{e.class} -- #{e.message}"
    end

    # Describe allows users to write rspec-like bare describe
    # blocks without declaring an inclosing control. Here, we
    # generate a control for them automatically and then execute
    # the describe block in the context of that control.
    #
    def describe(*args, &block)
      loc = block_location(block, caller(1..1).first)
      id = "(generated from #{loc} #{SecureRandom.hex})"

      res = nil

      rule = Inspec::Rule.new(id, profile_id, resources_dsl, {}) do
        res = describe(*args, &block)
      end

      tag_ids = control_tags(&block)

      if (controls_list_empty? && tags_list_empty?) || control_exist_in_controls_list?(id) || tag_exist_in_control_tags?(tag_ids)
        register_control(rule, &block)
      end

      res
    end

    def add_resource(name, new_res)
      resources_dsl.module_exec do
        define_method name.to_sym do |*args|
          new_res.new(@backend, name.to_s, *args)
        end
      end
    end

    def add_resources(context)
      # # TODO: write real unit tests for this and then make this change:
      # dsl = context.to_resources_dsl
      # self.class.include dsl
      # Inspec::Rule.include dsl

      self.class.class_eval do
        include context.to_resources_dsl
      end

      # TODO: seriously consider getting rid of the NPM model
      extend context.to_resources_dsl
    end

    def add_subcontext(context)
      profile_context_owner.add_subcontext(context)
    end

    def register_control(control, &block)
      if @skip_file
        ::Inspec::Rule.set_skip_rule(control, true, @skip_file_message)
      end

      unless profile_context_owner.profile_supports_platform?
        platform = inspec.platform
        msg = "Profile `#{profile_id}` is not supported on platform #{platform.name}/#{platform.release}."
        ::Inspec::Rule.set_skip_rule(control, true, msg)
      end

      unless profile_context_owner.profile_supports_inspec_version?
        msg = "Profile `#{profile_id}` is not supported on InSpec version (#{Inspec::VERSION})."
        ::Inspec::Rule.set_skip_rule(control, true, msg)
      end

      profile_context_owner.register_rule(control, &block) unless control.nil?
    end

    def input(input_name, options = {})
      if options.empty?
        # Simply an access, no event here
        Inspec::InputRegistry.find_or_register_input(input_name, profile_id).value
      else
        options[:priority] ||= 20
        options[:provider] = :inline_control_code
        evt = Inspec::Input.infer_event(options)
        Inspec::InputRegistry.find_or_register_input(input_name, profile_id, event: evt).value
      end
    end

    # Find the Input object, but don't collapse to a value.
    # Will return nil on a miss.
    def input_object(input_name)
      Inspec::InputRegistry.find_or_register_input(input_name, profile_id)
    end

    def attribute(name, options = {})
      Inspec.deprecate(:attrs_dsl, "Input name: #{name}, Profile: #{profile_id}")
      input(name, options)
    end

    def skip_control(id)
      profile_context_owner.unregister_rule(id)
    end
    alias skip_rule skip_control

    def only_if(message = nil, &block)
      return unless block
      return if @skip_file == true
      return if @skip_only_if_eval == true

      return if block.yield == true

      # Apply `set_skip_rule` for other rules in the same file
      profile_context_owner.rules.values.each do |r|
        sources_match = r.source_file == block.source_location[0]
        Inspec::Rule.set_skip_rule(r, true, message) if sources_match
      end

      @skip_file_message = message
      @skip_file = true
    end

    private

    def block_location(block, alternate_caller)
      if block.nil?
        alternate_caller[/^(.+:\d+):in .+$/, 1] || "unknown"
      else
        path, line = block.source_location
        "#{File.basename(path)}:#{line}"
      end
    end

    # Returns true if configuration hash is not empty and it contains the list of controls is not empty
    def profile_config_exist?
      !@conf.empty? && @conf.key?("profile") && !@conf["profile"].include_controls_list.empty?
    end

    def profile_tag_config_exist?
      !@conf.empty? && @conf.key?("profile") && !@conf["profile"].include_tags_list.empty?
    end

    # Returns true if configuration hash is empty or configuration hash does not have the list of controls that needs to be included
    def controls_list_empty?
      !@conf.empty? && @conf.key?("profile") && @conf["profile"].include_controls_list.empty? || @conf.empty?
    end

    def tags_list_empty?
      !@conf.empty? && @conf.key?("profile") && @conf["profile"].include_tags_list.empty? || @conf.empty?
    end

    # Check if the given control exist in the --controls option
    def control_exist_in_controls_list?(id)
      id_exist_in_list = false
      if profile_config_exist?
        id_exist_in_list = @conf["profile"].include_controls_list.any? do |inclusion|
          # Try to see if the inclusion is a regex, and if it matches
          inclusion == id || (inclusion.is_a?(Regexp) && inclusion =~ id)
        end
      end
      id_exist_in_list
    end

    # Check if the given control exist in the --tags option
    def tag_exist_in_control_tags?(tag_ids)
      tag_option_matches_with_list = false
      if !tag_ids.empty? && !tag_ids.nil? && profile_tag_config_exist?
        tag_option_matches_with_list = !(tag_ids & @conf["profile"].include_tags_list).empty?
        unless tag_option_matches_with_list
          @conf["profile"].include_tags_list.any? do |inclusion|
            # Try to see if the inclusion is a regex, and if it matches
            if inclusion.is_a?(Regexp)
              tag_ids.each do |id|
                tag_option_matches_with_list = (inclusion =~ id)
                break if tag_option_matches_with_list
              end
            end
          end
        end
      end
      tag_option_matches_with_list
    end
  end
end
