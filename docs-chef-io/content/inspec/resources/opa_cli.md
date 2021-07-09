+++
title = "opa_cli resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "opa_cli"
    identifier = "inspec/resources/os/opa_cli.md opa_cli resource"
    parent = "inspec/resources/os"
+++

Use the `opa_cli` Chef InSpec audit resource to query the OPA using the OPA policy file, data file and query.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

## Syntax

A `opa_cli` resource

    describe opa_cli(policy: "example.rego", data: "input.json", query: "data.example.allow") do
      its(["result"]) { should eq "value" }
    end

where

- `data` specifies the json formatted input data or file path.
- `policy` the path to policy file.
- `query` specifies the query to be run.
- `its(["result"]) { should eq "value" }` compares the results of the query against the expected result in the test

## parameters

`opa_cli` resource InSpec resource accepts `policy`, `data`, `query` and `opa_executable_path`

### `policy` _(required)_

Path to the OPA policy file.

### `data` _(required)_

This accepts input.json file or input data in json format.

### `query` _(required)_

Query input required to be evaluated against policy and input data.

### `opa_executable_path`

This is the full path to the OPA bindary or exe file used for running opa cli or opa commands. Default it will consider that the path is added in PATH variable.

## Examples

The following examples show how to use this Chef InSpec audit resource.

    describe opa_cli(query: "data.example.allow", policy: "example.rego", data: "input.json", opa_executable_path: "./opa") do
      its(["result", 0, "expressions", 0, "value"]) { should eq true }
      its("allow") { should eq "true" }
    end

Above example shows how `allow` value can be fetched in 2 ways.

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

## Properties

### allow

The `allow` property checks if specific input is as per the policy defined in OPA. If `allow` is not defined in the policy file then this matcher will not work.

    its('allow') { should eq 'value' }

