# encoding: utf-8

# Usage:
# describe npm('bower') do
#   it { should be_installed }
# end
class NpmPackage < Vulcano.resource(1)
  name 'npm'

  def initialize(package_name)
    @package_name = package_name
    @cache = nil
  end

  def info
    return @info unless @info.nil?

    cmd = vulcano.run_command("npm ls -g --json #{@package_name}")
    @info = {
      name: @package_name,
      type: 'npm',
      installed: cmd.exit_status == 0,
    }
    return @info unless @info[:installed]

    pkgs = JSON.parse(cmd.stdout)
    @info[:version] = pkgs['dependencies'][@package_name]['version']
    @info
  end

  def installed?
    info[:installed] == true
  end

  def version
    info[:version]
  end

  def to_s
    "npm package #{@package_name}"
  end
end
