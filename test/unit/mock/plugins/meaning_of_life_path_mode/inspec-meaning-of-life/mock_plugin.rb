module InspecPlugins
  module MeaningOfLife
    class MockPlugin < Inspec.plugin(2, :mock_plugin)

      # Do mockish things
      def execute(opts)
        return 42
      end
    end

  end
end