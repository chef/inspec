+++
title = "firewalld resource"
draft = false
gh_repo = "inspec"
platform = "linux"

[menu]
  [menu.inspec]
    title = "firewalld"
    identifier = "inspec/resources/os/firewalld.md firewalld resource"
    parent = "inspec/resources/os"
+++

Use the `firewalld` Chef InSpec audit resource to test that firewalld is configured to allow and deny access to specific hosts, services and ports on a system.

A firewalld has a number of zones that can be configured to allow and deny access to specific hosts, services, and ports.

## Availability

### Installation

This resource is distributed along with Chef InSpec itself. You can use it automatically.

### Version

This resource first became available in v1.40.0 of InSpec.

## Syntax

    describe firewalld do
      it { should be_running }
      its('default_zone') { should eq 'public' }
      it { should have_service_enabled_in_zone('ssh', 'public') }
      it { should have_rule_enabled('family=ipv4 source address=192.168.0.14 accept', 'public') }
    end

Use the where clause to test open interfaces, sources, and services in active zones.

    describe firewalld.where { zone == 'public' } do
      its('interfaces') { should cmp ['enp0s3', 'eno2'] }
      its('sources') { should cmp ['192.168.1.0/24', '192.168.1.2'] }
      its('services') { should cmp ['ssh', 'icmp'] }
      its('target') { should cmp ['default'] }
    end

## Properties

- `interfaces`
- `sources`
- `services`
- `target`
- `ports`
- `protocols`
- `forward_ports`
- `source_ports`
- `icmp_blocks`
- `rich_rules`

## Property Examples

### interfaces

The `interfaces` property is used in conjunction with the where class to display open interfaces in an active zone.

    describe firewalld.where { zone == 'public' } do
      its('interfaces') { should cmp ['enp0s3', 'eno2'] }
    end

### sources

The `sources` property is used in conjunction with the where class to display open sources in an active zone.

    describe firewalld.where { zone == 'public' } do
      its('sources') { should cmp ['192.168.1.0/24', '192.168.1.2'] }
    end

### services

The `services` property is used in conjunction with the where class to display open services in an active zone.

    describe firewalld.where { zone == 'public' } do
      its('services') { should cmp ['ssh', 'icmp'] }
    end

### target

The `target` property is used in conjunction with the where class to display the target action in an active zone.

    describe firewalld.where { zone == 'public' } do
      its('target') { should cmp ['default'] } # or ['DROP'], ['ACCEPT'], etc.
    end

### ports

The `ports` property is used in conjunction with the where class to display the ports used by an active zone.

    describe firewalld.where { zone == 'public' } do
      its('ports') { should cmp ["80/tcp", "443/tcp"] }
    end

### protocols

The `protocols` property is used in conjunction with the where class to display the protocols used by an active zone.

    describe firewalld.where { zone == 'public' } do
      its('protocols') { should cmp ["icmp", "ipv4"] }
    end

### default_zone

The `default_zone` property displays the default active zone to be used.

    its('default_zone') { should eq 'public' }

## Matchers

For a full list of available matchers, please visit our [matchers page](/inspec/matchers/).

### `be_installed`

The `be_installed` matcher tests if the firewalld service is installed:

    it { should be_installed }

### `be_running`

The `be_running` matcher tests if the firewalld service is running:

    it { should be_running }

### `have_zone`

`have_zone` returns true or false if the zone is set on firewalld. It does not mean the zone is active.

    it { should have_zone('public') }

### `have_service_enabled_in_zone`

`have_service_enabled_in_zone` returns true or false if the service is allowed in the specified zone.

    it { should have_service_enabled_in_zone('ssh', 'public') }

### `have_port_enabled_in_zone`

`have_port_enabled_in_zone` returns true or false if the port is allowed in the specified zone.

    it { should have_port_enabled_in_zone('22/tcp', 'public') }

### `have_rule_enabled`

`have_rule_enabled` returns true or false if the rich-rule has been specified in the zone.

    it { should have_rule_enabled('family=ipv4 source address=192.168.0.14 accept', 'public') }

It is not necessary to add the "rule" string, and you can start with the optional flags that are used in firewalld and end with the action.

### `have_icmp_block_inversion_enabled`

`have_icmp_block_inversion_enabled` returns true or false if ICMP block inversion flag is set for the indicated zone.

    it { should have_icmp_block_inversion_enabled }

### `have_masquerade_enabled`

`have_masquerade_enabled` returns true or false if the masquerade flag is set for the indicated zone.

    it { should have_masquerade_enabled }
