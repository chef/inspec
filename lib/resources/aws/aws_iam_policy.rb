require 'json'
require 'uri'

class AwsIamPolicy < Inspec.resource(1)
  name 'aws_iam_policy'
  desc 'Verifies settings for individual AWS IAM Policy'
  example "
    describe aws_iam_policy('AWSSupportAccess') do
      it { should be_attached }
    end
  "
  supports platform: 'aws'

  include AwsSingularResourceMixin

  attr_reader :arn, :attachment_count, :default_version_id

  EXPECTED_CRITERIA = %w{
    Action
    Effect
    Principal
    Resource
    Sid
  }.freeze

  UNIMPLEMENTED_CRITERIA = %w{
    Conditional
    NotAction
    NotPrincipal
    NotResource
  }.freeze

  def to_s
    "Policy #{@policy_name}"
  end

  def attached?
    !attachment_count.zero?
  end

  def attached_users
    return @attached_users if defined? @attached_users
    fetch_attached_entities
    @attached_users
  end

  def attached_groups
    return @attached_groups if defined? @attached_groups
    fetch_attached_entities
    @attached_groups
  end

  def attached_roles
    return @attached_roles if defined? @attached_roles
    fetch_attached_entities
    @attached_roles
  end

  def attached_to_user?(user_name)
    attached_users.include?(user_name)
  end

  def attached_to_group?(group_name)
    attached_groups.include?(group_name)
  end

  def attached_to_role?(role_name)
    attached_roles.include?(role_name)
  end

  def policy
    return nil unless exists?
    return @policy if defined?(@policy)

    catch_aws_errors do
      backend = BackendFactory.create(inspec_runner)
      gpv_response = backend.get_policy_version(policy_arn: arn, version_id: default_version_id)
      @policy = JSON.parse(URI.decode_www_form_component(gpv_response.document))
    end
    @policy
  end

  def statement_count
    return nil unless exists?
    policy['Statement'].count
  end

  def has_statement?(raw_criteria = {})
    return nil unless exists?
    criteria = has_statement__normalize_criteria(has_statement__validate_criteria(raw_criteria))
    # normalize statement structure
    # focus on SID
    # statements.any? do |statement|
    #   has_statement__effect(statement, criteria)
    #   has_statement__resource(statement, criteria)
    #   has_statement__action(statement, criteria)
    #   has_statement__principal(statement, criteria)
    # end
    false
  end

  private

  def has_statement__validate_criteria(raw_criteria)
    recognized_criteria = {}
    EXPECTED_CRITERIA.each do |expected_criterion|
      if raw_criteria.key?(expected_criterion)
        recognized_criteria[expected_criterion] = raw_criteria.delete(expected_criterion)
      end
    end

    UNIMPLEMENTED_CRITERIA.each do |unimplemented_criterion|
      if raw_criteria.key?(unimplemented_criterion)
        raise ArgumentError, "Criterion '#{unimplemented_criterion}' is not supported for performing have_statement queries."
      end
    end

    unless raw_criteria.empty?
      raise ArgumentError, "Unrecognized criteria #{raw_criteria.keys.join(', ')} to have_statement.  Recognized criteria: #{EXPECTED_CRITERIA.join(', ')}"
    end

    recognized_criteria
  end

  def has_statement__normalize_criteria(criteria)
    # Transform keys into lowercase symbols
    criteria.keys.each do |provided_key|
      criteria[provided_key.downcase.to_sym] = criteria.delete(provided_key)
    end

    # Check for array-valued criteria on Resources, Actions, and
    # Principals; set all_mode if seen
    [:actions, :principals, :resources].each do |criterion|
      if criteria.key?(criterion)
        criteria[(criterion.to_s + '_mode').to_sym] = criteria.kind_of(Array) ? :match_all : :match_any
      end
    end

    # Boost all criteria values into arrays
    [:actions, :principals, :resources].each do |criterion|
      if criteria.key?(criterion)
        criteria[criterion] = Array(criteria[criterion])
      end
    end

    criteria
  end

  def validate_params(raw_params)
    validated_params = check_resource_param_names(
      raw_params: raw_params,
      allowed_params: [:policy_name],
      allowed_scalar_name: :policy_name,
      allowed_scalar_type: String,
    )

    if validated_params.empty?
      raise ArgumentError, "You must provide the parameter 'policy_name' to aws_iam_policy."
    end

    validated_params
  end

  def fetch_from_api
    backend = BackendFactory.create(inspec_runner)

    policy = nil
    pagination_opts = { max_items: 1000 }
    loop do
      api_result = backend.list_policies(pagination_opts)
      policy = api_result.policies.detect do |p|
        p.policy_name == @policy_name
      end
      break if policy # Found it!
      break unless api_result.is_truncated # Not found and no more results
      pagination_opts[:marker] = api_result.marker
    end

    @exists = !policy.nil?

    return unless @exists
    @arn = policy[:arn]
    @default_version_id = policy[:default_version_id]
    @attachment_count = policy[:attachment_count]
  end

  def fetch_attached_entities
    unless @exists
      @attached_groups = nil
      @attached_users  = nil
      @attached_roles  = nil
      return
    end
    backend = AwsIamPolicy::BackendFactory.create(inspec_runner)
    criteria = { policy_arn: arn }
    resp = nil
    catch_aws_errors do
      resp = backend.list_entities_for_policy(criteria)
    end
    @attached_groups = resp.policy_groups.map(&:group_name)
    @attached_users  = resp.policy_users.map(&:user_name)
    @attached_roles  = resp.policy_roles.map(&:role_name)
  end

  class Backend
    class AwsClientApi < AwsBackendBase
      BackendFactory.set_default_backend(self)
      self.aws_client_class = Aws::IAM::Client

      def list_policies(criteria)
        aws_service_client.list_policies(criteria)
      end

      def list_entities_for_policy(criteria)
        aws_service_client.list_entities_for_policy(criteria)
      end
    end
  end
end
