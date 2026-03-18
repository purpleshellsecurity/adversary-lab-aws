variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "alert_email" {
  type        = string
  description = "Email address for HIGH/CRITICAL GuardDuty finding alerts"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
