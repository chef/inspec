require 'json'
require 'set'
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
    Resource
    Sid
  }.freeze

  UNIMPLEMENTED_CRITERIA = %w{
    Conditional
    NotAction
    NotPrincipal
    NotResource
    Principal
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
    @normalized_statements ||= has_statement__normalize_statements
    statements = has_statement__focus_on_sid(@normalized_statements, criteria)
    statements.any? do |statement|
      true && \
        has_statement__effect(statement, criteria) && \
        has_statement__array_criterion(:action, statement, criteria) && \
        has_statement__array_criterion(:resource, statement, criteria)
    end
  end

  private

  def has_statement__validate_criteria(raw_criteria)
    recognized_criteria = {}
    EXPECTED_CRITERIA.each do |expected_criterion|
      if raw_criteria.key?(expected_criterion)
        recognized_criteria[expected_criterion] = raw_criteria.delete(expected_criterion)
      end
    end

    # Special message for valid, but unimplemented statement attributes
    UNIMPLEMENTED_CRITERIA.each do |unimplemented_criterion|
      if raw_criteria.key?(unimplemented_criterion)
        raise ArgumentError, "Criterion '#{unimplemented_criterion}' is not supported for performing have_statement queries."
      end
    end

    # If anything is left, it's spurious
    unless raw_criteria.empty?
      raise ArgumentError, "Unrecognized criteria #{raw_criteria.keys.join(', ')} to have_statement.  Recognized criteria: #{EXPECTED_CRITERIA.join(', ')}"
    end

    # Effect has only 2 permitted values
    if recognized_criteria.key?('Effect')
      unless %w{Allow Deny}.include?(recognized_criteria['Effect'])
        raise ArgumentError, "Criterion 'Effect' for have_statement must be one of 'Allow' or 'Deny' - got '#{recognized_criteria['Effect']}'"
      end
    end

    recognized_criteria
  end

  def has_statement__normalize_criteria(criteria)
    # Transform keys into lowercase symbols
    criteria.keys.each do |provided_key|
      criteria[provided_key.downcase.to_sym] = criteria.delete(provided_key)
    end

    criteria
  end

  def has_statement__normalize_statements
    policy['Statement'].map do |statement|
      # Coerce some values into arrays
      %w{Action Resource}.each do |field|
        if statement.key?(field)
          statement[field] = Array(statement[field])
        end
      end

      # Symbolize all keys
      statement.keys.each do |field|
        statement[field.downcase.to_sym] = statement.delete(field)
      end

      statement
    end
  end

  def has_statement__focus_on_sid(statements, criteria)
    return statements unless criteria.key?(:sid)
    sid_seek = criteria[:sid]
    statements.select do |statement|
      if sid_seek.is_a? Regexp
        statement[:sid] =~ sid_seek
      else
        statement[:sid] == sid_seek
      end
    end
  end

  def has_statement__effect(statement, criteria)
    !criteria.key?(:effect) || criteria[:effect] == statement[:effect]
  end

  def has_statement__array_criterion(crit_name, statement, criteria)
    return true unless criteria.key?(crit_name)
    check = criteria[crit_name]
    values = statement[crit_name] # This is an array due to normalize_statements

    if check.is_a?(String)
      # If check is a string, it only has to match one of the values
      values.any? { |v| v == check }
    elsif check.is_a?(Regexp)
      # If check is a regex, it only has to match one of the values
      values.any? { |v| v =~ check }
    elsif check.is_a?(Array) && check.all? { |c| c.is_a? String }
      # If check is an array of strings, perform setwise check
      Set.new(values) == Set.new(check)
    elsif check.is_a?(Array) && check.all? { |c| c.is_a? Regexp }
      # If check is an array of regexes, all values must match all regexes
      values.all? { |v| check.all? { |r| v =~ r } }
    else
      false
    end
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
