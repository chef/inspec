require "helper"
require "inspec/resource"
require "inspec/resources/mongodb_session"

describe "Inspec::Resources::MongodbSession" do
  it "fails when no user, password" do
    resource = load_resource("mongodb_session", host: "localhost", port: 27017, database: "test")
    _(resource.resource_failed?).must_equal true
    _(resource.resource_exception_message).must_equal "Can't run MongoDB command. Error: Can't run MongoDB checks without authentication."
  end

  it "fails when no database name is provided" do
    resource = load_resource("mongodb_session", user: "foo", password: "bar", host: "localhost", port: 27017)
    _(resource.resource_failed?).must_equal true
    _(resource.resource_exception_message).must_equal "Can't run MongoDB command. Error: You must provide a database name for the session."
  end
end
