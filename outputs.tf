output "instance_id" {
  description = "ID of the lab EC2 instance"
  value       = module.ec2.instance_id
}

output "ssm_connect" {
  description = "Shell access via SSM — no SSH key or open ports needed"
  value       = module.ec2.ssm_connect
}

output "stop_vm" {
  description = "Command to stop the VM when not in use"
  value       = module.ec2.stop_vm
}

output "start_vm" {
  description = "Command to start the VM again"
  value       = module.ec2.start_vm
}

output "instance_role_arn" {
  description = "IAM role attached to the VM — stolen via IMDS in steal-instance-credentials TTP"
  value       = module.ec2.instance_role_arn
}

output "logs_bucket" {
  description = "S3 bucket containing CloudTrail logs"
  value       = module.storage.bucket_id
}

output "cloudtrail_log_group" {
  description = "CloudWatch Log Group — CloudTrail events"
  value       = module.cloudtrail.log_group_name
}

output "flow_log_group" {
  description = "CloudWatch Log Group — VPC Flow Logs"
  value       = module.networking.flow_log_group_name
}

output "host_auditd_log_group" {
  description = "CloudWatch Log Group — Auditd (process execution, file access, network)"
  value       = module.ec2.host_auditd_log_group
}

output "host_syslog_log_group" {
  description = "CloudWatch Log Group — Syslog (system events)"
  value       = module.ec2.host_syslog_log_group
}

output "host_auth_log_group" {
  description = "CloudWatch Log Group — Auth log (SSH, sudo, login events)"
  value       = module.ec2.host_auth_log_group
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = module.guardduty.detector_id
}

output "guardduty_console" {
  description = "Link to GuardDuty findings"
  value       = "https://${var.region}.console.aws.amazon.com/guardduty/"
}

output "cloudwatch_insights" {
  description = "Link to CloudWatch Insights"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home#logsV2:logs-insights"
}
