+++
title = "chrony_conf resource"
draft = false
gh_repo = "inspec"
platform = "linux"

[menu]
  [menu.inspec]
    title = "chrony_conf"
    identifier = "inspec/resources/os/chrony_conf.md chrony_conf resource"
    parent = "inspec/resources/os"
+++

Use the `chrony_conf` Chef InSpec audit resource to test the synchronization settings defined in the `chrony.conf` file. This file is typically located at `/etc/chrony.conf`.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

<!-- TODO: needs version number -->
<!-- ### Version

This resource first became available in v of InSpec. -->

## Syntax

An `chrony_conf` resource block declares the synchronization settings that should be tested:

    describe chrony_conf('path') do
      its('setting_name') { should eq 'value' }
    end

where

- `'setting_name'` is a synchronization setting defined in the `chrony.conf` file
- `('path')` is the non-default path to the `chrony.conf` file (default path is `/etc/chrony.conf`)
- `{ should eq 'value' }` is the value that is expected

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test for clock drift against named servers

    describe chrony_conf do
      its('driftfile') { should cmp '/var/lib/chrony/drift' }
      its('server') do
        should cmp [
          '0.ubuntu.pool.ntp.org',
          '1.ubuntu.pool.ntp.org',
          '2.ubuntu.pool.ntp.org'
        ]
      end
    end

## Matchers

This resource matches any service that is listed in the `chrony.conf` file. For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

    its('server') { should_not eq nil }

or:

    its('allow') { should include '192.168.0.0/16'}

For example:

    describe chrony_conf do
      its('server') { should_not eq nil }
      its('allow') { should include '192.168.0.0/16'}
    end
