+++
title = "sybase_session resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "sybase_session"
    identifier = "inspec/resources/os/sybase_session.md sybase_session resource"
    parent = "inspec/resources/os"
+++

Use the `sybase_session` Chef InSpec audit resource to test SQL commands run against a Sybase / SAP ASE database.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

### Requirements

The `isql` command line tool must be installed on the target system.

## Syntax

A `sybase_session` resource block declares the server, database, username and password to use for the session, and then the command to be run:

    describe sybase_session(database: 'pubs2', server: 'SYBASE', username: 'username', password: 'password').query('QUERY').row(0).column('result') do
      its('value') { should eq('expected') }
    end

where

- `sybase_session` declares a server, database, username and password with permission to run the query.
- `query('QUERY')` contains the query to be run
- `its('value') { should eq('expected') }` compares the results of the query against the expected result in the test

### Optional Parameters

#### bin

You may use the `bin` parameter to specify the path to the `isql` cli tool.

    describe sybase_session(database: 'pubs2',
                            server: 'SYBASE',
                            username: 'username',
                            password: 'password',
                            bin: '/opt/sap/OCS-16_0/bin/isql',
                          ).query('QUERY').row(0).column('result') do
      its('value') { should eq('expected') }
    end


#### sybase_home

You may use the `sybase_home` parameter to specify the path to the sybase installation.

    describe sybase_session(database: 'pubs2',
                            server: 'SYBASE',
                            username: 'username',
                            password: 'password',
                            sybase_home: '/opt/sap',
                          ).query('QUERY').row(0).column('result') do
      its('value') { should eq('expected') }
    end

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test for matching values in the pubs2 sample database

    sql = sybase_session(database: 'pubs2', server: 'SYBASE', username: 'my_user', password: 'password')

    describe sql.query("SELECT au_lname FROM authors").row(0).column('au_lname') do
      its("value") { should eq 'Bennet' }
    end

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

