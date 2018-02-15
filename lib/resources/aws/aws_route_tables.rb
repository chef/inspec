class AwsRouteTables < Inspec.resource(1)
  name 'aws_route_tables'
  desc 'Verifies settings for AWS Route Tables in bulk'
  example '
    describe aws_route_tables do
      it { should exist }
    end
  '
  supports platform: 'aws'

  include AwsPluralResourceMixin
  # Underlying FilterTable implementation.
  filter = FilterTable.create
  filter.add_accessor(:entries)
        .add(:exists?) { |x| !x.entries.empty? }
        .add(:vpc_ids, field: :vpc_id)
        .add(:route_table_ids, field: :route_table_id)
  filter.connect(self, :routes_data)

  def routes_data
    @table
  end

  def to_s
    'Route Tables'
  end

  private

  def validate_params(raw_criteria)
    unless raw_criteria.is_a? Hash
      raise 'Unrecognized criteria for fetching Route Tables. ' \
            "Use 'criteria: value' format."
    end

    # No criteria yet
    unless raw_criteria.empty?
      raise ArgumentError, 'aws_route_tables does not currently accept resource parameters.'
    end
    raw_criteria
  end

  def fetch_from_api
    backend = BackendFactory.create(inspec_runner)
    @table = backend.describe_route_tables({}).to_h[:route_tables] # max value for limit is 1000
  end

  class Backend
    class AwsClientApi < AwsBackendBase
      BackendFactory.set_default_backend self
      self.aws_client_class = Aws::EC2::Client

      def describe_route_tables(query = {})
        aws_service_client.describe_route_tables(query)
      end
    end
  end
end