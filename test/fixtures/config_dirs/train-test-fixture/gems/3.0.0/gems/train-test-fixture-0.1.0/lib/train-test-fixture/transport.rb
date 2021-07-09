require 'train-test-fixture/connection'

module TrainPlugins
  module TestFixture
    class Transport < Train.plugin(1)
      name 'test-fixture'

      def connection(_ = nil)
        @connection ||= TrainPlugins::TestFixture::Connection.new(@options)
      end

    end
  end
end
