+++
title = "mssql_sys_conf resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "mssql_sys_conf"
    identifier = "inspec/resources/os/mssql_sys_conf.md mssql_sys_conf resource"
    parent = "inspec/resources/os"
+++

Use the `mssql_sys_conf` Chef InSpec audit resource to test configuration of a Mssql database.

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

### Requirements

You must have database access.

## Syntax

A `mssql_sys_conf` resource block declares the configuration item name, user, and password to use.

    describe mssql_sys_conf("config item", user: 'USER', password: 'PASSWORD') do
      its("value_in_use") { should cmp "value" }
      its("value_configured") { should cmp "value" }
    end

where

- `mssql_sys_conf` declares a config item, user, and password with permission to use `sys.configurations`.
- `its('value_in_use') { should cmp 'expected' }` compares the current running value of the configuration item against an expected value
- `its('value_configured') { should cmp 'expected' }` compares the saved value of the configuration item against an expected value

### Optional Parameters

`mssql_sys_conf` is based on `mssql_session`, and accepts all parameters that `mssql_session` accepts.

#### `username`

Defaults to `SA`.

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test parameters set within the database view

    describe mssql_sys_conf("clr_enabled", user: 'USER', password: 'PASSWORD') do
      its("value_in_use") { should cmp "0" }
      its("value_configured") { should cmp "0" }
    end

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).
