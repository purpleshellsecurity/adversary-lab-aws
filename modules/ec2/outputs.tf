output "instance_id" {
  description = "ID of the lab EC2 instance"
  value       = aws_instance.lab.id
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the VM"
  value       = aws_iam_role.instance.arn
}

output "ssm_connect" {
  description = "Command to open a shell session via SSM"
  value       = "aws ssm start-session --target ${aws_instance.lab.id} --region ${var.region}"
}

output "stop_vm" {
  description = "Command to stop the VM when not in use"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.lab.id} --region ${var.region}"
}

output "start_vm" {
  description = "Command to start the VM again"
  value       = "aws ec2 start-instances --instance-ids ${aws_instance.lab.id} --region ${var.region}"
}

output "host_auditd_log_group" {
  description = "CloudWatch Log Group for auditd logs"
  value       = aws_cloudwatch_log_group.host_auditd.name
}

output "host_syslog_log_group" {
  description = "CloudWatch Log Group for syslog"
  value       = aws_cloudwatch_log_group.host_syslog.name
}

output "host_auth_log_group" {
  description = "CloudWatch Log Group for auth log"
  value       = aws_cloudwatch_log_group.host_auth.name
}
