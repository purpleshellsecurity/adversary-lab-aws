resource "aws_guardduty_detector" "lab" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  # Explicitly configure all data sources so behaviour is visible in code
  # - S3 protection enabled — monitors S3 data events for behavioral anomalies
  #   This demonstrates heuristic/ML-based detection (e.g. unusual access patterns,
  #   anomalous IPs reading objects) vs the rule-based management event detections.
  #   That distinction is core to detection engineering and worth having in the lab.
  #   Cost: charged per million S3 data events — minimal for a single-bucket lab.
  # - Kubernetes audit logs disabled — no EKS cluster in this lab
  # - EBS malware scanning disabled — charges per GB scanned, not useful here
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false
        }
      }
    }
  }

  tags = var.tags
}

# SNS topic for GuardDuty HIGH/CRITICAL finding alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "sns_policy" {
  statement {
    sid    = "AllowEventBridge"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

# EventBridge rule — routes HIGH/CRITICAL GuardDuty findings to SNS
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.project_name}-guardduty-alerts"
  description = "Route HIGH/CRITICAL GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 7] }] }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "SNSAlert"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      severity = "$.detail.severity"
      type     = "$.detail.type"
      title    = "$.detail.title"
      account  = "$.detail.accountId"
      region   = "$.region"
    }
    input_template = "\"GuardDuty Finding in <account> (<region>)\\nType:     <type>\\nSeverity: <severity>\\nTitle:    <title>\\n\\nView: https://<region>.console.aws.amazon.com/guardduty/home#/findings\""
  }
}
