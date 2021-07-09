+++
title = "opa_api resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "opa_api"
    identifier = "inspec/resources/os/opa_api.md mongodb_conf resource"
    parent = "inspec/resources/os"
+++

Use the `opa_api` Chef InSpec audit resource to query the OPA using the OPA url and data.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

## Syntax

A `opa_api` resource

    describe opa_api(url: "localhost:8181/v1/data/example/violation", data: "input.json") do
      its(["result"]) { should eq 'value' }
    end

where

- `'url'` specifies the url of the OPA server on which OPA is running.
- `'data'` specifies the json formatted data or json file.
- `its(["result"]) { should eq 'value' }` compares the results of the query against the expected result in the test

## parameters

`opa_api` resource InSpec resource accepts `url` and `data`

### `url` _(required)_

URL of the OPA API server.

### `data` _(required)_

This accepts input.json file or input data in json format.

## Examples

The following examples show how to use this Chef InSpec audit resource.

    describe opa_api(url: "localhost:8181/v1/data/example/allow", data: "input.json") do
      its(["result"]) { should eq true }
      its("allow") { should eq "true" }
    end

Above example shows how `allow` value can be fetched in 2 ways.

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

## Properties

### allow

The `allow` property checks if specific input is as per the policy defined in OPA. If `allow` is not defined in the policy file then this matcher will not work.

    its('allow') { should eq 'value' }
