variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
  default     = "detection-lab"
}

variable "region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "us-east-1"
}

variable "alert_email" {
  type        = string
  description = "Email address for alerts — GuardDuty HIGH/CRITICAL findings and monthly budget threshold."

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "budget_limit" {
  type        = number
  description = "Monthly budget limit in USD — alerts sent at 80% and 100% of this amount"
  default     = 50
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
  description = "CloudWatch log retention in days"
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch value: 1, 3, 5, 7, 14, 30, 60, 90, 180, or 365."
  }
}
