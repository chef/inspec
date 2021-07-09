require 'train-test-fixture/platform'
require 'train/transports/local'

module TrainPlugins
  module TestFixture
    class Connection < Train::Plugins::Transport::BaseConnection
      include TrainPlugins::TestFixture::Platform

      def initialize(options)
        super(options)
      end

      def local?
        true
      end

      private

      def run_command_via_connection(cmd)
        Train::Transports::Local::CommandResult.new(
          'Mock Command Result stdout',
          'Mock Command Result stderr',
          17
        )
      end

      def file_via_connection(path, *args)
        MockFile.new(self, path)
      end

      class MockFile < Train::File
        def content
          # Remarkably, the content is always the same.
          'Lorem Ipsum'
        end
      end
    end
  end
end
