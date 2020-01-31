require "functional/helper"

describe "inspec schema" do
  include FunctionalHelper

  describe "extracting the platforms schema export" do
    it "can execute a platforms schema command" do
      out = inspec("schema platforms --log-level=warn")

      data = JSON.parse(out.stdout)
      _(data.class).must_equal Array
      _(data.size).must_be(:>, 1)
      _(data[0]["name"]).must_equal "aix"
      families = %w{aix unix os}
      _(data[0]["families"]).must_equal families

      _(out.stderr).must_equal ""

      assert_exit_code 0, out
    end
  end
end
