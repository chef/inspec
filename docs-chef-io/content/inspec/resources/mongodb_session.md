+++
title = "mongodb_session resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "mongodb_session"
    identifier = "inspec/resources/os/mongodb_session.md mongodb_session resource"
    parent = "inspec/resources/os"
+++

Use the `mongodb_session` Chef InSpec audit resource to run MongoDB command against a MongoDB Database.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

## Syntax

A `mongodb_session` resource block declares the `user`, `password`, 'database' to use for the session, and then the command to be run:

  describe mongodb_session(user: "username", password: "password", database: "test").query(key: value) do
    its("params") { should match(/expected-result/) }
  end

where

- `mongodb_session` declares a user, password and database, connecting locally, with permission to run the query.
- `query` contains the query to be run.
- `its("params") { should eq(/expected-result/) }` compares the results of the query against the expected result in the test

### Optional Parameters

`mongodb_session` InSpec resource accepts `user`, `password`, `host`, `port`, `auth_source`, `auth_mech`, `ssl`, `ssl_cert`, `ssl_ca_cert`, `auth_mech_properties`.

In Particular:

#### `host`

Defaults to `127.0.0.1`

#### `port`

Defaults to `27017`

#### `auth_mech`

Defaults to `:scram`. The available opitions are `:scram256`, `:mongodb_x509`, `:aws`. Refer this [docs](https://docs.mongodb.com/ruby-driver/master/tutorials/ruby-driver-authentication/) for more understanding about these options.

#### `auth_source`

Defaults to given database name. `database` name is mandatory.

#### `ssl`

Defaults to false. Set `true ` to use ssl transport. For ssl realted options also refer to this [docs](https://docs.mongodb.com/ruby-driver/master/tutorials/ruby-driver-authentication/#client-certificate-x-509) for more understanding.

#### 'ssl_cert'

Path to ssl certificate file.

#### `ssl_ca_cert`

Path to ssl ca cert file.

#### `ssl_key`

Path to ssl key file.

#### `auth_mech_properties`

This accepts hash of authetication mechanism properties. This option is generally used with `aws` auth mechanism. Example of this is given in this docs [here](https://docs.mongodb.com/ruby-driver/master/tutorials/ruby-driver-authentication/#aws)

### MongodDB query reference docs

This resource is using mongo ruby driver to fetch the data.
[MongoDB Ruby Driver authentication](https://docs.mongodb.com/ruby-driver/master/tutorials/ruby-driver-authentication/)

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test the roles information using rolesInfo command of MongoDB

    describe mongodb_session(user: "foo", password: "bar", database: "test").query(rolesInfo: "dbAdmin").params["roles"].first do
      its(["role"]) { should eq "dbAdmin" }
    end

### Test the MongoDB user role.

    describe mongodb_session(user: "foo", password: "bar", database: "test").query(usersInfo: "foo").params["users"].first["roles"].first do
      its(["role"]) { should eq "readWrite" }
    end

### Test the params

    describe mongodb_session(user: "foo", password: "bar", database: "test").query(rolesInfo: "dbAdmin") do
      its("params") { should_not be_empty }
      its("params") { should include "roles" }
    end

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

### params

The `params` contains all the query data.
