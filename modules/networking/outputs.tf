output "vpc_id" {
  description = "ID of the detection lab VPC"
  value       = aws_vpc.lab.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the lab security group"
  value       = aws_security_group.lab.id
}

output "route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = aws_flow_log.lab.id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}
