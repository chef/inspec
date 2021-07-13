require "inspec/resources/command"

module Inspec::Resources
  class FirewallD < Inspec.resource(1)
    ###
    #  This recourse assumes that the file sudo vim /etc/polkit-1/rules.d/49-nopasswd_global.rules has been
    #  set to allow users in group "wheel" to perform any commands without authentication.
    ###

    name "firewalld"
    supports platform: "linux"
    desc "Use the firewalld resource to check and see if firewalld is configured to grand or deny access to specific hosts or services"
    example <<~EXAMPLE
      describe firewalld do
        it { should be_running }
        its('default_zone') { should eq 'public' }
        it { should have_service_enabled_in_zone('ssh', 'public') }
        it { should have_rule_enabled('rule family=ipv4 source address=192.168.0.14 accept', 'public') }
      end

      describe firewalld.where { zone == 'public' } do
        its('interfaces') { should cmp ['enp0s3', 'eno2'] }
        its('sources') { should cmp ['ssh', 'icmp'] }
        its('services') { should cmp ['192.168.1.0/24', '192.168.1.2'] }
      end
    EXAMPLE

    attr_reader :params

    filter = FilterTable.create
    filter.register_column(:zone, field: "zone")
      .register_column(:interfaces, field: "interfaces")
      .register_column(:sources,    field: "sources")
      .register_column(:services,   field: "services")
      .register_column(:target, field: "target")
      .register_column(:ports, field: "ports")
      .register_column(:protocols, field: "protocols")
      .register_column(:forward_ports, field: "forward_ports")
      .register_column(:source_ports, field: "source_ports")
      .register_column(:icmp_blocks, field: "icmp_blocks")
      .register_column(:rich_rules, field: "rich_rules")
      .register_custom_matcher(:icmp_block_inversion?) { |x| x.params[0]["icmp_block_inversion"] }
      .register_custom_matcher(:has_icmp_block_inversion_enabled?) { |x| x.params[0]["icmp_block_inversion"] }
      .register_custom_matcher(:masquerade?) { |x| x.params[0]["masquerade"] }
      .register_custom_matcher(:has_masquerade_enabled?) { |x| x.params[0]["masquerade"] }

    filter.install_filter_methods_on_resource(self, :params)

    def initialize
      @params = parse_active_zones(active_zones)
    end

    def installed?
      inspec.command("firewall-cmd").exist?
    end

    def has_zone?(query_zone)
      return false unless installed?

      result = firewalld_command("--get-zones").split(" ")
      result.include?(query_zone)
    end

    def running?
      return false unless installed?

      result = firewalld_command("--state")
      result =~ /^running/ ? true : false
    end

    def default_zone
      # return: word associated with the name of the default zone
      # example: 'public'
      firewalld_command("--get-default-zone")
    end

    def has_service_enabled_in_zone?(query_service, query_zone = default_zone)
      firewalld_command("--permanent --zone=#{query_zone} --query-service=#{query_service}") == "yes"
    end

    def service_ports_enabled_in_zone(query_service, query_zone = default_zone)
      # return: String of ports open
      # example: ['22/tcp', '4722/tcp']
      firewalld_command("--permanent --zone=#{query_zone} --service=#{query_service} --get-ports").split(" ")
    end

    def service_protocols_enabled_in_zone(query_service, query_zone = default_zone)
      # return: String of protocols open
      # example: ['icmp', 'ipv4', 'igmp']
      firewalld_command("--permanent --zone=#{query_zone} --service=#{query_service} --get-protocols").split(" ")
    end

    def has_port_enabled_in_zone?(query_port, query_zone = default_zone)
      firewalld_command("--permanent --zone=#{query_zone} --query-port=#{query_port}") == "yes"
    end

    def has_rule_enabled?(rule, query_zone = default_zone)
      rule = "rule #{rule}" unless rule.start_with?("rule")
      firewalld_command("--permanent --zone=#{query_zone} --query-rich-rule='#{rule}'") == "yes"
    end

    def to_s
      "Firewall Rules"
    end

    private

    def active_zones
      # return syntax:
      #   [default-zone-name]
      #       interfaces: [open interfases]
      #
      # example:
      #   public
      #       interfaces: enp0s3
      firewalld_command("--get-active-zones")
    end

    def parse_active_zones(content)
      # Split by every second line, which contains the zone and the interfaces.
      content = content.split(/\n/).each_slice(2).map { |slice| slice.join("\n") }
      content.map do |line|
        parse_line(line)
      end.compact
    end

    def parse_line(line)
      zone = line.split("\n")[0]
      {
        "zone" => zone,
        "interfaces" => line.split(":")[1].split(" "),
        "services" => services_bound(zone),
        "sources" => sources_bound(zone),
        "target" => target_bound(zone),
        "icmp_block_inversion" => icmp_block_inversion_bound?(zone),
        "ports" => ports_bound(zone),
        "protocols" => protocols_bound(zone),
        "masquerade" => masquerade_bound?(zone),
        "forward_ports" => forward_ports_bound(zone),
        "source_ports" => source_ports_bound(zone),
        "icmp_blocks" => icmp_blocks_bound(zone),
        "rich_rules" => rich_rules_bound(zone),
      }
    end

    def target_bound(query_zone)
      # result: a target bound for the zone
      # example: 'DROP'
      firewalld_command("--permanent --zone=#{query_zone} --get-target").strip
    end

    def icmp_block_inversion_bound?(query_zone)
      # result: true/false whether inversion of icmp blocks has been enabled for a zone
      # example: true
      firewalld_command("--permanent --zone=#{query_zone} --query-icmp-block-inversion") == "yes"
    end

    def ports_bound(query_zone)
      # result: a list of ports bound for a zone
      # example: ['80/tcp', '443/tcp']
      firewalld_command("--permanent --zone=#{query_zone} --list-ports").split(" ")
    end

    def protocols_bound(query_zone)
      # result: a list of protocols added for a zone
      # example: ['icmp', 'ipv4', 'igmp']
      firewalld_command("--permanent --zone=#{query_zone} --list-protocols").split(" ")
    end

    def masquerade_bound?(query_zone)
      # result: true/false whether IPv4 masquerading has been enabled for a zone
      # example: true
      firewalld_command("--permanent --zone=#{query_zone} --query-masquerade") == "yes"
    end

    def forward_ports_bound(query_zone)
      # result: a list of IPv4 forward ports bound to a zone
      # example: ['port=80:proto=tcp:toport=88', 'port=12345:proto=tcp:toport=54321:toaddr=192.168.1.3']
      firewalld_command("--permanent --zone=#{query_zone} --list-forward-ports").split("\n")
    end

    def source_ports_bound(query_zone)
      # result: a list of source ports bound to a zone
      # example: ['80/tcp', '8080/tcp']
      firewalld_command("--permanent --zone=#{query_zone} --list-source-ports").split(" ")
    end

    def icmp_blocks_bound(query_zone)
      # result: a list of internet ICMP type blocks bound to a zone
      # example: ['echo-request', 'echo-reply']
      firewalld_command("--permanent --zone=#{query_zone} --list-icmp-blocks").split(" ")
    end

    def rich_rules_bound(query_zone)
      # result: a list of rich language rules bound to a zone
      # example: ['rule protocol value="ah" accept', 'rule service name="ftp" log limit value="1/m" audit accept']
      firewalld_command("--permanent --zone=#{query_zone} --list-rich-rules").split("\n")
    end

    def sources_bound(query_zone)
      # result: a list containing either an ip address or ip address with a mask, or a ipset or an ipset with the ipset prefix.
      # example: ['192.168.0.4', '192.168.0.0/16', '2111:DB28:ABC:12::', '2111:db89:ab3d:0112::0/64']
      firewalld_command("--permanent --zone=#{query_zone} --list-sources").split(" ")
    end

    def services_bound(query_zone)
      # result: a list of services bound to a zone.
      # example: ['ssh', 'dhcpv6-client']
      firewalld_command("--permanent --zone=#{query_zone} --list-services").split(" ")
    end

    def firewalld_command(command)
      command = "firewall-cmd #{command}"
      result = inspec.command(command)
      if result.stderr != ""
        return "Error on command #{command}: #{result.stderr}"
      end

      result.stdout.strip
    end
  end
end