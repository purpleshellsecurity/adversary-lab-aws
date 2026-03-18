variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet to launch the instance into"
}

variable "security_group_id" {
  type        = string
  description = "ID of the security group to attach to the instance"
}

variable "auto_shutdown_hour" {
  type        = number
  description = "UTC hour at which the VM shuts itself down via cron (0-23)"
  default     = 23

  validation {
    condition     = var.auto_shutdown_hour >= 0 && var.auto_shutdown_hour <= 23
    error_message = "auto_shutdown_hour must be between 0 and 23."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days for host logs"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
