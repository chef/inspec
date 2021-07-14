require "inspec/exceptions"

module FilterTable
  # This is used as a sentinel value in custom property filtering
  module NoCriteriaProvided; end

  class ExceptionCatcher
    def initialize(original_resource, original_exception)
      @original_resource = original_resource
      @original_exception = original_exception
    end

    # This method is called via the runner and signals RSpec to output a block
    # showing why the resource was skipped. This prevents the resource from
    # being added to the test collection and being evaluated.
    def resource_skipped?
      @original_exception.is_a?(Inspec::Exceptions::ResourceSkipped)
    end

    # This method is called via the runner and signals RSpec to output a block
    # showing why the resource failed. This prevents the resource from
    # being added to the test collection and being evaluated.
    def resource_failed?
      @original_exception.is_a?(Inspec::Exceptions::ResourceFailed)
    end

    def resource_exception_message
      @original_exception.message
    end

    # Capture message chains and return `ExceptionCatcher` objects
    def method_missing(*)
      self
    end

    # RSpec will check the object returned to see if it responds to a method
    # before calling it. We need to fake it out and tell it that it does. This
    # allows it to skip past that check and fall through to #method_missing
    def respond_to?(_method, include_all = false)
      true
    end

    def to_s
      "#{@original_resource} (#{@original_exception.message})"
    end
    alias inspect to_s

    # Rspec is not able to convert FilterTable::ExceptionCatcher issue https://github.com/inspec/inspec/issues/5369
    # which result into not showing actual exception message this allows to convert it properly.
    def to_ary
      [ to_s ]
    end
  end

  class Trace
    def initialize
      @chain = []
    end

    %w{== != >= > < <= =~ !~}.each do |m|
      define_method m.to_sym do |*args|
        res = Trace.new
        @chain.push([[m.to_sym] + args, res])
        res
      end
    end

    def method_missing(*args)
      res = Trace.new
      @chain.push([args, res])
      res
    end

    def self.to_ruby(trace)
      chain = trace.instance_variable_get(:@chain)
      return "" if chain.empty?

      " " + chain.map do |el|
        m = el[0][0]
        args = el[0].drop(1)
        nxt = to_ruby(el[1])
        next m.to_s + nxt if args.empty?
        next m.to_s + " " + args[0].inspect + nxt if args.length == 1

        m.to_s + "(" + args.map(&:inspect).join(", ") + ")" + nxt
      end.join(" ")
    end
  end

  class Table
    attr_reader :raw_data, :resource_instance, :criteria_string
    def initialize(resource_instance, raw_data, criteria_string)
      @resource_instance = resource_instance
      @raw_data = raw_data
      @raw_data = [] if @raw_data.nil?
      @criteria_string = criteria_string
      @populated_lazy_columns = {}
    end

    # Filter the raw data based on criteria (as method params) or by evaling a
    # block; then construct a new Table of the same class as ourselves,
    # wrapping the filtered data, and return it.
    def where(conditions = {}, &block)
      return self unless conditions.is_a?(Hash)
      return self if conditions.empty? && !block_given?

      # Initialize the details of the new Table.
      new_criteria_string = criteria_string
      filtered_raw_data = raw_data

      # If we were provided params, interpret them as criteria to be evaluated
      # against the raw data. Criteria are assumed to be hash keys.
      conditions.each do |raw_field_name, desired_value|
        raise(ArgumentError, "'#{decorate_symbols(raw_field_name)}' is not a recognized criterion - expected one of #{decorate_symbols(list_fields).join(", ")}'") unless field?(raw_field_name)

        populate_lazy_field(raw_field_name, desired_value) if is_field_lazy?(raw_field_name)
        new_criteria_string += " #{raw_field_name} == #{desired_value.inspect}"
        filtered_raw_data = filter_raw_data(filtered_raw_data, raw_field_name, desired_value)
      end

      # If we were given a block, make a special Struct for each row, that has an accessor
      # for each field declared using `register_custom_property`, then instance-eval the block
      # against the struct.
      if block_given?
        # Perform the filtering.
        filtered_raw_data = filtered_raw_data.find_all { |row_as_hash| create_eval_context_for_row(row_as_hash, "").instance_eval(&block) }
        # Try to interpret the block for updating the stringification.
        src = Trace.new
        # Swallow any exceptions raised here.
        # See https://github.com/chef/inspec/issues/2929
        begin
          src.instance_eval(&block)
        rescue # rubocop: disable Lint/HandleExceptions
          # Yes, robocop, ignoring all exceptions is normally
          # a bad idea.  Here, an exception just means we don't
          # understand what was in a `where` block, so we can't
          # meaningfully sytringify it.  We still have a decent
          # default stringification.
        end
        new_criteria_string += Trace.to_ruby(src)
      end

      self.class.new(resource, filtered_raw_data, new_criteria_string)
    end

    def create_eval_context_for_row(*_)
      raise "#{self.class} must not be used on its own. It must be inherited "\
           "and the #create_eval_context_for_row method must be implemented. This is an internal "\
           "error and should not happen."
    end

    def resource
      resource_instance
    end

    def params
      # TODO: consider deprecating
      raw_data
    end

    def entries
      row_criteria_string = resource.to_s + criteria_string + " one entry"
      raw_data.map do |row|
        create_eval_context_for_row(row, row_criteria_string)
      end
    end

    def get_column_values(field)
      raw_data.map do |row|
        row[field]
      end
    end

    def list_fields
      @__fields_in_raw_data ||= raw_data.reduce([]) do |fields, row|
        fields.concat(row.keys).uniq
      end
    end

    def field?(proposed_field)
      # Currently we only know about a field if it is present in a at least one row of the raw data.
      # If we have no rows in the raw data, assume all fields are acceptable (and rely on failing to match on value, nil)
      return true if raw_data.empty?

      # Most resources have Symbol keys in their raw data.  Some have Strings (looking at you, `shadow`).
      is_field = false
      is_field ||= list_fields.include?(proposed_field.to_s)
      is_field ||= list_fields.include?(proposed_field.to_sym)
      is_field ||= is_field_lazy?(proposed_field.to_s)
      is_field ||= is_field_lazy?(proposed_field.to_sym)

      is_field
    end

    def to_s
      resource.to_s + criteria_string
    end

    alias inspect to_s

    def populate_lazy_field(field_name, criterion)
      return unless is_field_lazy?(field_name)
      return if field_populated?(field_name)

      raw_data.each do |row|
        next if row.key?(field_name) # skip row if pre-existing data is present

        callback_for_lazy_field(field_name).call(row, criterion, self)
      end
      mark_lazy_field_populated(field_name)
    end

    def is_field_lazy?(sought_field_name)
      custom_properties_schema.values.any? do |property_struct|
        sought_field_name == property_struct.field_name && \
          property_struct.opts[:lazy]
      end
    end

    def callback_for_lazy_field(field_name)
      return unless is_field_lazy?(field_name)

      custom_properties_schema.values.find do |property_struct|
        property_struct.field_name == field_name
      end.opts[:lazy]
    end

    def field_populated?(field_name)
      @populated_lazy_columns[field_name]
    end

    def mark_lazy_field_populated(field_name)
      @populated_lazy_columns[field_name] = true
    end

    private

    def matches_float(x, y)
      return false if x.nil?
      return false if !x.is_a?(Float) && (x =~ /\A[-+]?(\d+\.?\d*|\.\d+)\z/).nil?

      x.to_f == y
    end

    def matches_int(x, y)
      return false if x.nil?
      return false if !x.is_a?(Integer) && (x =~ /\A[-+]?\d+\z/).nil?

      x.to_i == y
    end

    def matches_regex(x, y)
      return x == y if x.is_a?(Regexp)

      !x.to_s.match(y).nil?
    end

    def matches(x, y)
      y === x # rubocop:disable Style/CaseEquality
    end

    def filter_raw_data(current_raw_data, field, desired_value)
      return [] if current_raw_data.empty?

      method_ref = case desired_value
                   when Float   then :matches_float
                   when Integer then :matches_int
                   when Regexp  then :matches_regex
                   else              :matches
                   end

      assume_symbolic_keyed_data = current_raw_data.first.keys.first.is_a? Symbol
      field = assume_symbolic_keyed_data ? field.to_sym : field.to_s

      current_raw_data.find_all do |row|
        next unless row.key?(field)

        send(method_ref, row[field], desired_value)
      end
    end

    def decorate_symbols(thing)
      return thing.map { |t| decorate_symbols(t) } if thing.is_a?(Array)
      return ":" + thing.to_s if thing.is_a? Symbol
      return thing + " (String)" if thing.is_a? String

      thing
    end
  end

  class Factory
    CustomPropertyType = Struct.new(:field_name, :block, :opts)

    def initialize
      @filter_methods = %i{where entries raw_data}
      @custom_properties = {}
      register_custom_matcher(:exist?) { |table| !table.raw_data.empty? }
      register_custom_property(:count) { |table|  table.raw_data.count }

      @resource = nil # TODO: this variable is never initialized
    end

    def install_filter_methods_on_resource(resource_class, raw_data_fetcher_method_name) # rubocop: disable Metrics/AbcSize, Metrics/MethodLength
      # A context in which you can access the fields as accessors
      non_block_struct_fields = @custom_properties.values.reject(&:block).map(&:field_name)
      unless non_block_struct_fields.empty?
        row_eval_context_type = Struct.new(*non_block_struct_fields.map(&:to_sym)) do
          attr_accessor :criteria_string
          attr_accessor :filter_table
          def to_s
            @criteria_string || super
          end
        end
      end

      properties_to_define = @custom_properties.map do |method_name, custom_property_structure|
        { method_name: method_name, method_body: create_custom_property_body(custom_property_structure) }
      end

      # Define the filter table subclass
      custom_properties = @custom_properties # We need a local var, not an instance var, for a closure below
      table_class = Class.new(Table) do
        # Install each custom property onto the FilterTable subclass
        properties_to_define.each do |property_info|
          define_method property_info[:method_name], &property_info[:method_body]
        end

        define_method :custom_properties_schema do
          custom_properties
        end

        # Install a method that can wrap all the fields into a context with accessors
        define_method :create_eval_context_for_row do |row_as_hash, criteria_string = ""|
          return row_eval_context_type.new if row_as_hash.nil?

          context = row_eval_context_type.new(*non_block_struct_fields.map { |field| row_as_hash[field] })
          context.criteria_string = criteria_string
          context.filter_table = self
          context
        end
      end

      # Now that the table class is defined and the row eval context struct is defined,
      # extend the row eval context struct to support triggering population of lazy fields
      # in where blocks. To do that, we'll need a reference to the table (which
      # knows which fields are populated, and how to populate them) and we'll need to
      # override the getter method for each lazy field, so it will trigger
      # population if needed.  Keep in mind we don't have to adjust the constructor
      # args of the row struct; also the Struct class will already have provided
      # a setter for each field.
      @custom_properties.values.each do |property_info|
        next unless property_info.opts[:lazy]

        field_name = property_info.field_name.to_sym
        row_eval_context_type.send(:define_method, field_name) do
          unless filter_table.field_populated?(field_name)
            filter_table.populate_lazy_field(field_name, NoCriteriaProvided) # No access to criteria here
            # OK, the underlying raw data has the value in the first row
            # (because we would trigger population only on the first row)
            # We could just return the value, but we need to set it on this Struct in case it is referenced multiple times
            # in the where block.
            self[field_name] = filter_table.raw_data[0][field_name]
          end
          # Now return the value using the Struct getter, whether newly populated or not
          self[field_name]
        end
      end

      # Define all access methods with the parent resource
      # These methods will be configured to return an `ExceptionCatcher` object
      # that will always return the original exception, but only when called
      # upon. This will allow method chains in `describe` statements to pass the
      # `instance_eval` when loaded and only throw-and-catch the exception when
      # the tests are run.
      methods_to_install_on_resource_class = @filter_methods + @custom_properties.keys
      methods_to_install_on_resource_class.each do |method_name|
        resource_class.send(:define_method, method_name) do |*args, &block|

          # self here is the resource instance
          filter_table_instance = table_class.new(self, send(raw_data_fetcher_method_name), " with")
          filter_table_instance.send(method_name, *args, &block)
        rescue Inspec::Exceptions::ResourceFailed, Inspec::Exceptions::ResourceSkipped => e
          FilterTable::ExceptionCatcher.new(resource_class, e)

        end
      end
    end

    alias connect install_filter_methods_on_resource

    # TODO: This should almost certainly be privatized.  Every FilterTable client should get :entries and :where;
    # InSpec core resources do not define anything else, other than azure_generic_resource, which is likely a mis-use.
    def register_filter_method(method_name)
      if method_name.nil?
        # TODO: @resource is never initialized
        throw RuntimeError, "Called filter.add_accessor for resource #{@resource} with method name nil!"
      end
      if @filter_methods.include? method_name.to_sym
        # TODO: issue deprecation warning?
      else
        @filter_methods.push(method_name.to_sym)
      end
      self
    end

    alias add_accessor register_filter_method

    def register_custom_property(property_name, opts = {}, &property_implementation)
      if property_name.nil?
        # TODO: @resource is never initialized
        throw RuntimeError, "Called filter.add for resource #{@resource} with method name nil!"
      end

      if @custom_properties.key?(property_name.to_sym)
        # TODO: issue deprecation warning?
      else
        @custom_properties[property_name.to_sym] =
          CustomPropertyType.new(opts[:field] || property_name, property_implementation, opts)
      end
      self
    end

    alias add register_custom_property
    alias register_column register_custom_property
    alias register_custom_matcher register_custom_property

    private

    # This provides the implementation for methods requested using
    # register_custom_property(:some_method_name, opts, &block)
    # Some usage in the wild involves people passing a desired value to the generated method, like:
    #  things.ids(23)
    # I'm calling this the 'filter_criterion_value'. I speculate that a default value is
    # provided here so that users can meaningfully query for nil.
    def create_custom_property_body(custom_property_struct)
      if !custom_property_struct.block.nil?
        # If the custom method provided its own block, rely on it.
        lambda do |filter_criteria_value = NoCriteriaProvided|
          # Here self is an instance of the FilterTable subclass that wraps the raw data.
          # Call the block with two args - the table instance, and any filter criteria value.
          custom_property_struct.block.call(self, filter_criteria_value)
        end
      else
        # No block definition, so the property was registered using (field: :some_field)
        # This does however support passing a block to this method, and filtering using it, like Enumerable#select.
        lambda do |filter_criteria_value = NoCriteriaProvided, &cond_block|
          if filter_criteria_value == NoCriteriaProvided && !block_given?
            # No second-order block given.  Just return an array of the values in the selected column.
            result = where(nil)
            if custom_property_struct.opts[:lazy]
              result.populate_lazy_field(custom_property_struct.field_name, filter_criteria_value)
            end
            result = where(nil).get_column_values(custom_property_struct.field_name) # TODO: the where(nil). is likely unneeded
            result = result.flatten.uniq.compact if custom_property_struct.opts[:style] == :simple
            result
          else
            # A secondary block was provided.  Rely on where() to execute the block, while also filtering on any single value
            # Suspected bug: if filter_criteria_value == NoCriteriaProvided, this is unlikely to match - see hash condition handling in where() above.
            where(custom_property_struct.field_name => filter_criteria_value, &cond_block)
          end
        end
      end
    end
  end

  def self.create
    Factory.new
  end
end
