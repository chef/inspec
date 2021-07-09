require 'train-test-fixture/version'

module TrainPlugins
  module TestFixture
    module Platform
      def platform
        # Build this platform's family declarations.
        # You'll need at least unix and windows to make the file() resource work.
        Train::Platforms.name('test-fixture').in_family('unix')
        Train::Platforms.name('test-fixture').in_family('windows')
        force_platform!('test-fixture',
          release: TrainPlugins::TestFixture::VERSION,
          arch: 'mock',
        )
      end
    end
  end
end
