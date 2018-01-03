# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'resources/platform'

module Inspec::Resources
  class OSResource < PlatformResource
    name 'os'
    desc 'Use the os InSpec audit resource to test the platform on which the system is running.'
    example "
      describe os[:family] do
        it { should eq 'redhat' }
      end

      describe os.redhat? do
        it { should eq true }
      end

      describe os.linux? do
        it { should eq true }
      end
    "

    # reuse helper methods from backend
    %w{aix? redhat? debian? suse? bsd? solaris? linux? unix? windows? hpux? darwin?}.each do |os_family|
      define_method(os_family.to_sym) do
        @platform.send(os_family)
      end
    end

    # helper to collect a hash object easily
    def params
      {
        name: @platform[:name],
        family: @platform[:family],
        release: @platform[:release],
        arch: @platform[:arch],
      }
    end

    def to_s
      'Operating System Detection'
    end
  end
end
