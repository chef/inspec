require "helper"
require "inspec/resource"
require "inspec/resources/oracledb_listener_conf"

describe "Inspec::Resources::OracledbListenerConf" do
  it "verify listener settings of oracle DB in linux when listener conf path is passed" do
    resource = MockLoader.new(:centos7).load_resource("oracledb_listener_conf", "/opt/oracle/product/18c/dbhomeXE/network/admin/listener.ora")
    _(resource.params["DEFAULT_SERVICE_LISTENER"]).must_equal "XE"
    _(resource.params["EM_EXPRESS_PORT"]).must_equal "5500"
  end

  it "verify listener settings of oracle DB in windows when listener conf path is passed" do
    resource = MockLoader.new(:windows).load_resource("oracledb_listener_conf", "C:\\app\\Administrator\\product\\18.0.0\\dbhomeXE\\network\\admin\\listener.ora")
    _(resource.params["DEFAULT_SERVICE_LISTENER"]).must_equal "XE"
    _(resource.params["EM_EXPRESS_PORT"]).must_equal "5500"
  end

  it "verify listener settings of oracle DB in linux when listener conf path is not passed" do
    resource = MockLoader.new(:centos7).load_resource("oracledb_listener_conf", nil)
    _(resource.params["DEFAULT_SERVICE_LISTENER"]).must_equal "XE"
    _(resource.params["EM_EXPRESS_PORT"]).must_equal "5500"
  end

  it "verify listener settings of oracle DB in windows when listener conf path is not passed" do
    resource = MockLoader.new(:windows).load_resource("oracledb_listener_conf", nil)
    _(resource.params["DEFAULT_SERVICE_LISTENER"]).must_equal "XE"
    _(resource.params["EM_EXPRESS_PORT"]).must_equal "5500"
  end
end
