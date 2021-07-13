require "helper"
require "inspec/resource"
require "inspec/resources/firewalld"

describe "Inspec::Resources::FirewallD" do
  cent_resource = MockLoader.new(:centos7).load_resource("firewalld")

  it "verify firewalld detects a zone" do
    _(cent_resource.has_zone?("public")).must_equal true
    _(cent_resource.has_zone?("zonenotinfirewalld")).must_equal false
  end

  it "verify firewalld is running" do
    _(cent_resource.running?).must_equal true
  end

  it "verify firewalld detects a default_zone" do
    _(cent_resource.default_zone).must_equal "public"
  end

  it "parses zones with multiple interfaces" do
    entries = cent_resource.where { zone == "public" }
    _(entries.interfaces).must_equal [%w{enp0s3 eno2}]
  end

  it "detects services in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.services).must_equal [%w{ssh icmp}]
  end

  it "detects multiple active zones" do
    entries = cent_resource.where { zone == "public" }
    _(entries.interfaces).must_equal [%w{enp0s3 eno2}]
    entries = cent_resource.where { zone == "default" }
    _(entries.interfaces).must_equal [["enp0s3"]]
  end

  it "detects sources in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.sources).must_equal [["192.168.1.0/24", "192.168.1.2"]]
  end

  it "detects target in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.target).must_equal ["default"]
  end

  it "detects whether ICMP block inversion is enabled in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.icmp_block_inversion?).must_equal false
  end

  it "detects ports in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.ports).must_equal [["80/tcp", "443/tcp"]]
  end

  it "detects protocols in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.protocols).must_equal [%w{icmp ipv4}]
  end

  it "detects whether IPv4 masquerading is enabled in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.masquerade?).must_equal false
  end

  it "detects IPv4 forward ports in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.forward_ports).must_equal [["port=80:proto=tcp:toport=88:toaddr=", "port=12345:proto=tcp:toport=54321:toaddr=192.168.1.3"]]
  end

  it "detects source ports in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.source_ports).must_equal [["80/tcp", "8080/tcp"]]
  end

  it "detects ICMP blocks in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.icmp_blocks).must_equal [%w{echo-request echo-reply}]
  end

  it "detects rich rules in an active zone" do
    entries = cent_resource.where { zone == "public" }
    _(entries.rich_rules).must_equal [["rule protocol value=\"ah\" accept", "rule service name=\"ftp\" log limit value=\"1/m\" audit accept"]]
  end

  it "verify firewalld detects a whether or not a service is allowed in a zone" do
    _(cent_resource.has_service_enabled_in_zone?("ssh", "public")).must_equal true
  end

  it "verify firewalld detects ports enabled for a service in a zone" do
    _(cent_resource.service_ports_enabled_in_zone("ssh", "public")).must_equal ["22/tcp"]
  end

  it "verify firewalld detects protocols enabled for a service in a zone" do
    _(cent_resource.service_protocols_enabled_in_zone("ssh", "public")).must_equal ["icmp"]
  end

  it "verify firewalld detects a whether or not a port is allowed in a zone" do
    _(cent_resource.has_port_enabled_in_zone?("22/udp", "public")).must_equal true
  end

  it "verify firewalld detects a whether or not a rule is enabled in a zone included rule text" do
    _(cent_resource.has_rule_enabled?("rule family=ipv4 source address=192.168.0.14 accept", "public")).must_equal true
  end

  it "verify firewalld detects a whether or not a rule is enabled in a zone exluding rule text" do
    _(cent_resource.has_rule_enabled?("family=ipv4 source address=192.168.0.14 accept", "public")).must_equal true
  end
end
