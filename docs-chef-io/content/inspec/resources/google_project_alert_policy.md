+++
title = "google_project_alert_policy resource"
draft = false
gh_repo = "inspec"
platform = "gcp"

[menu]
  [menu.inspec]
    title = "google_project_alert_policy"
    identifier = "inspec/resources/gcp/google_project_alert_policy.md google_project_alert_policy resource"
    parent = "inspec/resources/gcp"
+++

## Syntax

A `google_project_alert_policy` is used to test a Google AlertPolicy resource

## Examples

```ruby
describe.one do
  google_project_alert_policies(project: 'chef-gcp-inspec').policy_names.each do |policy_name|
    describe google_project_alert_policy(project: 'chef-gcp-inspec', name: policy_name.split('/').last) do
      it { should exist }
      its('display_name') { should cmp 'Display'}
      its('combiner') { should cmp 'OR'}
      it { should be_enabled }
    end
  end
end
```

### Test that a GCP alert policy is enabled

    describe google_project_alert_policy(policy: 'spaterson', name: '9271751234503117449') do
      it { should be_enabled }
    end

### Test that a GCP compute alert policy display name is correct

    describe google_project_alert_policy(policy: 'spaterson-project', name: '9271751234503117449') do
      its('display_name') { should eq 'policy name' }
    end

## Properties

Properties that can be accessed from the `google_project_alert_policy` resource:

`name`
: The unique resource name for this policy. Its syntax is: projects/[PROJECT_ID]/alertPolicies/[ALERT_POLICY_ID]

`display_name`
: A short name or phrase used to identify the policy in dashboards, notifications, and incidents. To avoid confusion, don't use the same display name for multiple policies in the same project. The name is limited to 512 Unicode characters.

`combiner`
: How to combine the results of multiple conditions to determine if an incident should be opened.

  Possible values:

  - AND
  - OR
  - AND_WITH_MATCHING_RESOURCE

`creation_record`
: A read-only record of the creation of the alerting policy. If provided in a call to create or update, this field will be ignored.

  `mutate_time`
  : When the change occurred.

  `mutated_by`
  : The email address of the user making the change.

`enabled`
: Whether or not the policy is enabled. The default is true.

`conditions`
: A list of conditions for the policy. The conditions are combined by AND or OR according to the combiner field. If the combined conditions evaluate to true, then an incident is created. A policy can have from one to six conditions.

  `condition_absent`
  : A condition that checks that a time series continues to receive new data points.

    `aggregations`
    : Specifies the alignment of data points in individual time series as well as how to combine the retrieved time series together (such as when aggregating multiple streams on each resource to a single stream for each resource or when aggregating streams across all members of a group of resources). Multiple aggregations are applied in the order specified.

      `per_series_aligner`
      : The approach to be used to align individual time series. Not all alignment functions may be applied to all time series, depending on the metric type and value type of the original time series. Alignment may change the metric type or the value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - ALIGN_NONE
        - ALIGN_DELTA
        - ALIGN_RATE
        - ALIGN_INTERPOLATE
        - ALIGN_NEXT_OLDER
        - ALIGN_MIN
        - ALIGN_MAX
        - ALIGN_MEAN
        - ALIGN_COUNT
        - ALIGN_SUM
        - ALIGN_STDDEV
        - ALIGN_COUNT_TRUE
        - ALIGN_COUNT_FALSE
        - ALIGN_FRACTION_TRUE
        - ALIGN_PERCENTILE_99
        - ALIGN_PERCENTILE_95
        - ALIGN_PERCENTILE_50
        - ALIGN_PERCENTILE_05
        - ALIGN_PERCENT_CHANGE

      `group_by_fields`
      : The set of fields to preserve when crossSeriesReducer is specified. The groupByFields determine how the time series are partitioned into subsets prior to applying the aggregation function. Each subset contains time series that have the same value for each of the grouping fields. Each individual time series is a member of exactly one subset. The crossSeriesReducer is applied to each subset of time series. It is not possible to reduce across different resource types, so this field implicitly contains resource.type. Fields not specified in groupByFields are aggregated away. If groupByFields is not specified and all the time series have the same resource type, then the time series are aggregated into a single output time series. If crossSeriesReducer is not defined, this field is ignored.

      `alignment_period`
      : The alignment period for per-time series alignment. If present, alignmentPeriod must be at least 60 seconds. After per-time series alignment, each time series will contain data points only on the period boundaries. If perSeriesAligner is not specified or equals ALIGN_NONE, then this field is ignored. If perSeriesAligner is specified and does not equal ALIGN_NONE, then this field must be defined; otherwise an error is returned.

      `cross_series_reducer`
      : The approach to be used to combine time series. Not all reducer functions may be applied to all time series, depending on the metric type and the value type of the original time series. Reduction may change the metric type of value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - REDUCE_NONE
        - REDUCE_MEAN
        - REDUCE_MIN
        - REDUCE_MAX
        - REDUCE_SUM
        - REDUCE_STDDEV
        - REDUCE_COUNT
        - REDUCE_COUNT_TRUE
        - REDUCE_COUNT_FALSE
        - REDUCE_FRACTION_TRUE
        - REDUCE_PERCENTILE_99
        - REDUCE_PERCENTILE_95
        - REDUCE_PERCENTILE_50
        - REDUCE_PERCENTILE_05

    `trigger`
    : The number/percent of time series for which the comparison must hold in order for the condition to trigger. If unspecified, then the condition will trigger if the comparison is true for any of the time series that have been identified by filter and aggregations.

      `percent`
      : The percentage of time series that must fail the predicate for the condition to be triggered.

      `count`
      : The absolute number of time series that must fail the predicate for the condition to be triggered.

    `duration`
    : The amount of time that a time series must fail to report new data to be considered failing. Currently, only values that are a multiple of a minute--e.g. 60s, 120s, or 300s --are supported.

    `filter`
    : A filter that identifies which time series should be compared with the threshold.The filter is similar to the one that is specified in the MetricService.ListTimeSeries request (that call is useful to verify the time series that will be retrieved / processed) and must specify the metric type and optionally may contain restrictions on resource type, resource labels, and metric labels. This field may not exceed 2048 Unicode characters in length.

  `name`
  : The unique resource name for this condition. Its syntax is: projects/[PROJECT_ID]/alertPolicies/[POLICY_ID]/conditions/[CONDITION_ID] [CONDITION_ID] is assigned by Stackdriver Monitoring when the condition is created as part of a new or updated alerting policy.

  `condition_threshold`
  : A condition that compares a time series against a threshold.

    `threshold_value`
    : A value against which to compare the time series.

    `denominator_filter`
    : A filter that identifies a time series that should be used as the denominator of a ratio that will be compared with the threshold. If a denominator_filter is specified, the time series specified by the filter field will be used as the numerator.The filter is similar to the one that is specified in the MetricService.ListTimeSeries request (that call is useful to verify the time series that will be retrieved / processed) and must specify the metric type and optionally may contain restrictions on resource type, resource labels, and metric labels. This field may not exceed 2048 Unicode characters in length.

    `denominator_aggregations`
    : Specifies the alignment of data points in individual time series selected by denominatorFilter as well as how to combine the retrieved time series together (such as when aggregating multiple streams on each resource to a single stream for each resource or when aggregating streams across all members of a group of resources).When computing ratios, the aggregations and denominator_aggregations fields must use the same alignment period and produce time series that have the same periodicity and labels.This field is similar to the one in the MetricService.ListTimeSeries request. It is advisable to use the ListTimeSeries method when debugging this field.

      `per_series_aligner`
      : The approach to be used to align individual time series. Not all alignment functions may be applied to all time series, depending on the metric type and value type of the original time series. Alignment may change the metric type or the value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - ALIGN_NONE
        - ALIGN_DELTA
        - ALIGN_RATE
        - ALIGN_INTERPOLATE
        - ALIGN_NEXT_OLDER
        - ALIGN_MIN
        - ALIGN_MAX
        - ALIGN_MEAN
        - ALIGN_COUNT
        - ALIGN_SUM
        - ALIGN_STDDEV
        - ALIGN_COUNT_TRUE
        - ALIGN_COUNT_FALSE
        - ALIGN_FRACTION_TRUE
        - ALIGN_PERCENTILE_99
        - ALIGN_PERCENTILE_95
        - ALIGN_PERCENTILE_50
        - ALIGN_PERCENTILE_05
        - ALIGN_PERCENT_CHANGE

      `group_by_fields`
      : The set of fields to preserve when crossSeriesReducer is specified. The groupByFields determine how the time series are partitioned into subsets prior to applying the aggregation function. Each subset contains time series that have the same value for each of the grouping fields. Each individual time series is a member of exactly one subset. The crossSeriesReducer is applied to each subset of time series. It is not possible to reduce across different resource types, so this field implicitly contains resource.type. Fields not specified in groupByFields are aggregated away. If groupByFields is not specified and all the time series have the same resource type, then the time series are aggregated into a single output time series. If crossSeriesReducer is not defined, this field is ignored.

      `alignment_period`
      : The alignment period for per-time series alignment. If present, alignmentPeriod must be at least 60 seconds. After per-time series alignment, each time series will contain data points only on the period boundaries. If perSeriesAligner is not specified or equals ALIGN_NONE, then this field is ignored. If perSeriesAligner is specified and does not equal ALIGN_NONE, then this field must be defined; otherwise an error is returned.

      `cross_series_reducer`
      : The approach to be used to combine time series. Not all reducer functions may be applied to all time series, depending on the metric type and the value type of the original time series. Reduction may change the metric type of value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - REDUCE_NONE
        - REDUCE_MEAN
        - REDUCE_MIN
        - REDUCE_MAX
        - REDUCE_SUM
        - REDUCE_STDDEV
        - REDUCE_COUNT
        - REDUCE_COUNT_TRUE
        - REDUCE_COUNT_FALSE
        - REDUCE_FRACTION_TRUE
        - REDUCE_PERCENTILE_99
        - REDUCE_PERCENTILE_95
        - REDUCE_PERCENTILE_50
        - REDUCE_PERCENTILE_05

    `duration`
    : The amount of time that a time series must violate the threshold to be considered failing. Currently, only values that are a multiple of a minute--e.g., 0, 60, 120, or 300 seconds--are supported. If an invalid value is given, an error will be returned. When choosing a duration, it is useful to keep in mind the frequency of the underlying time series data (which may also be affected by any alignments specified in the aggregations field); a good duration is long enough so that a single outlier does not generate spurious alerts, but short enough that unhealthy states are detected and alerted on quickly.

    `comparison`
    : The comparison to apply between the time series (indicated by filter and aggregation) and the threshold (indicated by threshold_value). The comparison is applied on each time series, with the time series on the left-hand side and the threshold on the right-hand side. Only COMPARISON_LT and COMPARISON_GT are supported currently.

      Possible values:

      - COMPARISON_GT
      - COMPARISON_GE
      - COMPARISON_LT
      - COMPARISON_LE
      - COMPARISON_EQ
      - COMPARISON_NE

    `trigger`
    : The number/percent of time series for which the comparison must hold in order for the condition to trigger. If unspecified, then the condition will trigger if the comparison is true for any of the time series that have been identified by filter and aggregations, or by the ratio, if denominator_filter and denominator_aggregations are specified.

      `percent`
      : The percentage of time series that must fail the predicate for the condition to be triggered.

      `count`
      : The absolute number of time series that must fail the predicate for the condition to be triggered.

    `aggregations`
    : Specifies the alignment of data points in individual time series as well as how to combine the retrieved time series together (such as when aggregating multiple streams on each resource to a single stream for each resource or when aggregating streams across all members of a group of resources). Multiple aggregations are applied in the order specified.This field is similar to the one in the MetricService.ListTimeSeries request. It is advisable to use the ListTimeSeries method when debugging this field.

      `per_series_aligner`
      : The approach to be used to align individual time series. Not all alignment functions may be applied to all time series, depending on the metric type and value type of the original time series. Alignment may change the metric type or the value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - ALIGN_NONE
        - ALIGN_DELTA
        - ALIGN_RATE
        - ALIGN_INTERPOLATE
        - ALIGN_NEXT_OLDER
        - ALIGN_MIN
        - ALIGN_MAX
        - ALIGN_MEAN
        - ALIGN_COUNT
        - ALIGN_SUM
        - ALIGN_STDDEV
        - ALIGN_COUNT_TRUE
        - ALIGN_COUNT_FALSE
        - ALIGN_FRACTION_TRUE
        - ALIGN_PERCENTILE_99
        - ALIGN_PERCENTILE_95
        - ALIGN_PERCENTILE_50
        - ALIGN_PERCENTILE_05
        - ALIGN_PERCENT_CHANGE

      `group_by_fields`
      : The set of fields to preserve when crossSeriesReducer is specified. The groupByFields determine how the time series are partitioned into subsets prior to applying the aggregation function. Each subset contains time series that have the same value for each of the grouping fields. Each individual time series is a member of exactly one subset. The crossSeriesReducer is applied to each subset of time series. It is not possible to reduce across different resource types, so this field implicitly contains resource.type. Fields not specified in groupByFields are aggregated away. If groupByFields is not specified and all the time series have the same resource type, then the time series are aggregated into a single output time series. If crossSeriesReducer is not defined, this field is ignored.

      `alignment_period`
      : The alignment period for per-time series alignment. If present, alignmentPeriod must be at least 60 seconds. After per-time series alignment, each time series will contain data points only on the period boundaries. If perSeriesAligner is not specified or equals ALIGN_NONE, then this field is ignored. If perSeriesAligner is specified and does not equal ALIGN_NONE, then this field must be defined; otherwise an error is returned.

      `cross_series_reducer`
      : The approach to be used to combine time series. Not all reducer functions may be applied to all time series, depending on the metric type and the value type of the original time series. Reduction may change the metric type of value type of the time series.Time series data must be aligned in order to perform cross- time series reduction. If crossSeriesReducer is specified, then perSeriesAligner must be specified and not equal ALIGN_NONE and alignmentPeriod must be specified; otherwise, an error is returned.

        Possible values:

        - REDUCE_NONE
        - REDUCE_MEAN
        - REDUCE_MIN
        - REDUCE_MAX
        - REDUCE_SUM
        - REDUCE_STDDEV
        - REDUCE_COUNT
        - REDUCE_COUNT_TRUE
        - REDUCE_COUNT_FALSE
        - REDUCE_FRACTION_TRUE
        - REDUCE_PERCENTILE_99
        - REDUCE_PERCENTILE_95
        - REDUCE_PERCENTILE_50
        - REDUCE_PERCENTILE_05

    `filter`
    : A filter that identifies which time series should be compared with the threshold.The filter is similar to the one that is specified in the MetricService.ListTimeSeries request (that call is useful to verify the time series that will be retrieved / processed) and must specify the metric type and optionally may contain restrictions on resource type, resource labels, and metric labels. This field may not exceed 2048 Unicode characters in length.

  `display_name`
  : A short name or phrase used to identify the condition in dashboards, notifications, and incidents. To avoid confusion, don't use the same display name for multiple conditions in the same policy.

`notification_channels`
: Identifies the notification channels to which notifications should be sent when incidents are opened or closed or when new violations occur on an already opened incident. Each element of this array corresponds to the name field in each of the NotificationChannel objects that are returned from the notificationChannels.list method. The syntax of the entries in this field is `projects/[PROJECT_ID]/notificationChannels/[CHANNEL_ID]`

`user_labels`
: This field is intended to be used for organizing and identifying the AlertPolicy objects.The field can contain up to 64 entries. Each key and value is limited to 63 Unicode characters or 128 bytes, whichever is smaller. Labels and values can contain only lowercase letters, numerals, underscores, and dashes. Keys must begin with a letter.

`documentation`
: A short name or phrase used to identify the policy in dashboards, notifications, and incidents. To avoid confusion, don't use the same display name for multiple policies in the same project. The name is limited to 512 Unicode characters.

  `content`
  : The text of the documentation, interpreted according to mimeType. The content may not exceed 8,192 Unicode characters and may not exceed more than 10,240 bytes when encoded in UTF-8 format, whichever is smaller.

  `mime_type`
  : The format of the content field. Presently, only the value "text/markdown" is supported.

## GCP Permissions

Ensure the [Stackdriver Monitoring API](https://console.cloud.google.com/apis/library/monitoring.googleapis.com/) is enabled for the current project.
