require "set"

# We disable this for the sake of legibility
# rubocop:disable Layout/AlignHash

# These elements are shared between more than one output type

module Schema
  ######################### Establish simple helpers for this schema ########################################
  # Use this function to easily make described types
  def self.desc(obj, description)
    obj.merge({ "description" => description })
  end

  # Use this function to easily make an array of a type
  def self.array(of_type)
    {
      "type" => "array",
      "items" => of_type,
    }
  end

  # Use this class to quickly add/use object types to/in a definition block
  class SchemaType
    attr_accessor :name, :depends
    def initialize(name, body, dependencies)
      # The title of the type
      @name = name
      # The body of the type
      @body = body
      # What SchemaType[]s it depends on. In essence, any thing that you .ref in the body
      @depends = Set.new(dependencies)
      # As an added check, go through properties if it exists
      if body.key?("properties")
        if body.key?("required")
          body["required"].each do |k|
            if not body["properties"].key?(k)
              raise "Property #{k} is required in schema #{name} but does not exist!"
            end
          end
        else
          raise "Objects in schema must have a \"required\" property, even if it is empty"
        end
      end
    end

    # Produce this schema types generated body.
    # Use to actually define the ref!
    def body
      @body.merge({
          "title" => @name,
          "type" => "object",
      })
    end

    # Yields this type as a json schema ref
    def ref
      { "$ref" => "#/definitions/#{@name}" }
    end

    # Recursively acquire all depends for this schema. Return them sorted by name
    def all_depends
      result = @depends
      # Fetch all from children
      @depends.each do |nested_type|
        # Yes, converting back to set here does some duplicate sorting.
        # But here, performance really isn't our concern.
        result += Set.new(nested_type.all_depends)
      end
      # Return the results as a sorted array
      Array(result).sort_by { |type| type.name }
    end
  end

  ######################### Establish basic type shorthands for this schema ########################################
  # These three are essentially primitives, used as shorthand
  OBJECT = { "type" => "object", "additionalProperties" => true }.freeze
  NUMBER = { "type" => "number" }.freeze
  STRING = { "type" => "string" }.freeze

  # A controls tags can have any number of properties, and any sorts of values
  TAGS = { "type" => "object", "additionalProperties" => true }.freeze

  # Attributes/Inputs specify the inputs to a profile.
  # TODO: We need better specifications on this
  INPUT = { "type" => "object", "additionalProperties" => true }.freeze

  # Within a control file, impacts can be numeric 0-1 or string in [none,low,medium,high,critical]
  # However, when they are output, the string types are automatically converted as follows:
  # none      -> 0    to 0.01
  # low       -> 0.01 to 0.4
  # medium    -> 0.4  to 0.7
  # high      -> 0.7  to 0.9
  # Critical  -> 0.9  to 1.0 (inclusive)
  IMPACT = {
    "type" => "number",
    "minimum" => 0.0,
    "maximum" => 1.0,
  }.freeze

  # A status for a control
  STATUS = {
    "type" => "string",
    "enum" => %w{passed failed skipped error},
  }.freeze

  ######################### Establish inspec types common to several schemas helpers for this schema #######################################

  # We use "title" to name the type.
  # and "description" (via the describe function) to describe its particular usage
  # Summary item containing run statistics about a subset of the controls
  STATISTIC_ITEM = SchemaType.new("Statistic Block", {
    "additionalProperties" => false,
    "required" => ["total"],
    "properties" => {
      "total" => desc(NUMBER, "Total number of controls (in this category) for this inspec execution."),
    },
  }, [])

  # Bundles several results statistics, representing distinct groups of controls
  STATISTIC_GROUPING = SchemaType.new("Statistic Hash", {
    "additionalProperties" => false,
    "required" => [],
    "properties" => {
        "passed"  => STATISTIC_ITEM.ref,
        "skipped" => STATISTIC_ITEM.ref,
        "failed"  => STATISTIC_ITEM.ref,
    },
  }, [STATISTIC_ITEM])

  # Contains statistics of an exec run.
  STATISTICS = SchemaType.new("Statistics", {
    "additionalProperties" => false,
    "required" => ["duration"],
    "properties" => {
      "duration" => desc(NUMBER, "How long (in seconds) this inspec exec ran for."),
      "controls" => desc(STATISTIC_GROUPING.ref, "Breakdowns of control statistics by result"),
    },
  }, [STATISTIC_GROUPING])

  # Represents the platform the test was run on
  PLATFORM = SchemaType.new("Platform", {
    "additionalProperties" => false,
    "required" => %w{name release},
    "properties" => {
      "name"      => desc(STRING, "The name of the platform this was run on."),
      "release"   => desc(STRING, "The version of the platform this was run on."),
      "target_id" => desc(STRING, "TODO: Document this property"),
    },
  }, [])

  # Explains what software ran the inspec profile/made this file. Typically inspec but could in theory be a different software
  GENERATOR = SchemaType.new("Generator", {
    "additionalProperties"  => false,
    "required"              => %w{name version},
    "properties"            => {
      "name"    => desc(STRING, "The name of the software that generated this report."),
      "version" => desc(STRING, "The version of the software that generated this report."),
    },
  }, [])


  # Occurs from "exec --reporter json" and "inspec json"
  # Denotes what file this control comes from, and where within
  SOURCE_LOCATION = SchemaType.new("Source Location", {
    "additionalProperties"  => false,
    "properties"            => {
      "ref"   => desc(STRING, "Path to the file that this statement originates from"),
      "line"  => desc(NUMBER, "The line at which this statement is located in the file"),
    },
    "required" => %w{ref line},
  }, [])

  # References an external document
  # TODO: One of these needs to be deprecated. For now both are supported
  REFERENCE = SchemaType.new("Reference", {
    # Needs at least one of title (ref), url, or uri.
    "anyOf" => [
      {
        "required"   => ["ref"],
        "properties" => { "ref" => STRING },
      },
      {
        "required"   => ["url"],
        "properties" => { "url" => STRING },
      },
      {
        "required"   => ["uri"],
        "properties" => { "uri" => STRING },
      },
    ],
  }, [])

  # Represents a group of controls within a profile/.rb file
  CONTROL_GROUP = SchemaType.new("Control Group", {
    "additionalProperties"  => false,
    "required"              => %w{id controls},
    "properties"            => {
      "id"        => desc(STRING, "The unique identifier of the group"),
      "title"     => desc(STRING, "The name of the group"),
      "controls"  => desc(array(STRING), "The control IDs in this group"),
    },
  }, [])

  # Occurs from "inspec exec --reporter json" and "inspec json"
  # Represents a platfrom or group of platforms that this profile supports
  SUPPORT = SchemaType.new("Supported Platform", {
    "additionalProperties"  => false,
    "required"              => ["platform-family"],
    "properties"            => {
      "platform-family" => STRING,
      "platform-name"   => STRING,
      "platform"        => STRING,
      # os-* supports are being deprecated
      "os-family"       => STRING,
      "os-name"         => STRING,
    },
  }, [])

end
