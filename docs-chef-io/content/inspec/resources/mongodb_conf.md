+++
title = "mongodb_conf resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "mongodb_conf"
    identifier = "inspec/resources/os/mongodb_conf.md mongodb_conf resource"
    parent = "inspec/resources/os"
+++

Use the `mongodb_conf` Chef InSpec audit resource to test the contents of the configuration file for MongoDB, typically located at `/etc/mongod.conf` or `C:\Program Files\MongoDB\Server\<version>\bin\mongod.cfg`, depending on the platform.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

## Syntax

A `mongodb_conf` resource block declares one (or more) settings in the `mongodb.conf` file, and then compares the setting in the configuration file to the value stated in the test:

    describe mongodb_conf('path') do
      its('setting') { should eq 'value' }
    end

where

- `'setting'` specifies a setting in the `mongodb.conf` file
- `('path')` is the non-default path to the `mongodb.conf` file (optional)
- `should eq 'value'` is the value that is expected

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test the key management configuration options

    describe mongodb_conf do
      its(["security", "enableEncryption"]) { should eq true }
    end

### Test the port on which MongoDB listens

    describe mongodb_conf do
      its(["net", "port"]) { should eq 27017 }
    end

### Test the security configuration options

    describe mongodb_conf do
      its(["security", "authorization"]) { should eq "enabled" }
    end


## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

