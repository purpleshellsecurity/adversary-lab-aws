resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/detection-lab/cloudtrail/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    sid       = "CloudTrailCWLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role" "cloudtrail" {
  name               = "${var.project_name}-cloudtrail-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cloudtrail" {
  name   = "CloudTrailCWLogs"
  role   = aws_iam_role.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

# IAM changes take time to propagate globally — without this wait CloudTrail
# hits CannotAssumeRole on first deployment and never delivers to CloudWatch
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy.cloudtrail]
  create_duration = "30s"
}

resource "aws_cloudtrail" "lab" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = var.logs_bucket_id
  s3_key_prefix                 = "cloudtrail"
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  depends_on = [time_sleep.iam_propagation]

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = var.tags
}

# ── Metric Filters ────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_metric_filter" "unauthorized_api" {
  name           = "UnauthorizedAPICalls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"AccessDenied\") || ($.errorCode = \"UnauthorizedOperation\") }"

  metric_transformation {
    name          = "UnauthorizedAPICalls"
    namespace     = "DetectionLab/${var.project_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "RootAccountUsage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name          = "RootAccountUsage"
    namespace     = "DetectionLab/${var.project_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "console_no_mfa" {
  name           = "ConsoleLoginNoMFA"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventName = \"ConsoleLogin\" && $.additionalEventData.MFAUsed != \"Yes\" }"

  metric_transformation {
    name          = "ConsoleLoginNoMFA"
    namespace     = "DetectionLab/${var.project_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "IAMUserChanges"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = CreateUser) || ($.eventName = DeleteUser) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = CreateAccessKey) || ($.eventName = CreateLoginProfile) }"

  metric_transformation {
    name          = "IAMUserChanges"
    namespace     = "DetectionLab/${var.project_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "cloudtrail_changes" {
  name           = "CloudTrailChanges"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = StopLogging) || ($.eventName = DeleteTrail) || ($.eventName = UpdateTrail) }"

  metric_transformation {
    name          = "CloudTrailChanges"
    namespace     = "DetectionLab/${var.project_name}"
    value         = "1"
    default_value = "0"
  }
}
