output "log_group_name" {
  description = "CloudWatch Log Group name — select this in Insights to query CloudTrail events"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN"
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "trail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.lab.arn
}
