require "lib/inspec/schema/primitives"

# These type occur only when running "inspec json <file>".

module Inspec
  module Schema
    module ProfileJson
      # Represents descriptions. Can have any string => string pairing
      CONTROL_DESCRIPTIONS = Primitives::SchemaType.new("Profile JSON Control Descriptions", {
        "type" => "object",
        "aditionalProperties" => Primitives::STRING,
        "required" => [],
      }, [])

      # Represents a control that hasn't been run
      # Differs slightly from a normal control, in that it lacks results, and its descriptions are different
      # TODO: Attempt to unify this with the CONTROL type
      CONTROL = Primitives::SchemaType.new("Profile JSON Control", {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w{id title desc descriptions impact refs tags code source_location},
        "properties" => {
          "id" => Primitives.desc(Primitives::STRING, "The ID of this control"),
          "title" => { "type" => %w{string null} },
          "desc" => { "type" => %w{string null} },
          "descriptions" => CONTROL_DESCRIPTIONS.ref,
          "impact" => Primitives::IMPACT,
          "refs" => Primitives.array(Primitives::REFERENCE.ref),
          "tags" => Primitives::TAGS,
          "code" => Primitives.desc(Primitives::STRING, "The raw source code of the control. Note that if this is an overlay control, it does not include the underlying source code"),
          "source_location" => Primitives::SOURCE_LOCATION.ref,
        },
      }, [CONTROL_DESCRIPTIONS, Primitives::REFERENCE, Primitives::SOURCE_LOCATION])

      # A profile that has not been run.
      # TODO: Try to unify with the exec version
      PROFILE = Primitives::SchemaType.new("Profile JSON Profile", {
        "type" => "object",
        "additionalProperties" => true, # Anything in the yaml will be put in here
        "required" => %w{name supports controls groups inputs sha256 status},
        "properties" => {
          "name" => Primitives::STRING,
          "supports" => Primitives.array(Primitives::SUPPORT.ref),
          "controls" => Primitives.array(CONTROL.ref),
          "groups" => Primitives.array(Primitives::CONTROL_GROUP.ref),
          "inputs" => Primitives.array(Primitives::INPUT),
          "sha256" => Primitives::STRING,
          "status" => Primitives::STRING,
          "generator" => Primitives::GENERATOR.ref,

          # Other properties recommended in inspec docs, but that aren"t guaranteed
          "title" => Primitives::STRING,
          "maintainer" => Primitives::STRING,
          "copyright" => Primitives::STRING,
          "copyright_email" => Primitives::STRING,
        },
      }, [Primitives::SUPPORT, CONTROL, Primitives::CONTROL_GROUP, Primitives::GENERATOR])
    end
  end
end
