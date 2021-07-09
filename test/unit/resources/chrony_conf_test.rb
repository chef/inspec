require "helper"
require "inspec/resource"
require "inspec/resources/chrony_conf"

describe "Inspec::Resources::ChronyConf" do
  it "verify chrony config parsing" do
    resource = load_resource("chrony_conf")
    _(resource.driftfile).must_equal "/var/lib/chrony/drift"
    _(resource.pool).must_equal [
      "0.ubuntu.pool.ntp.org iburst",
      "1.ubuntu.pool.ntp.org iburst",
    ]
    _(resource.server).must_equal %w{
      127.127.1.0 127.127.1.1
    }
    assert_nil resource.allow
  end
end
