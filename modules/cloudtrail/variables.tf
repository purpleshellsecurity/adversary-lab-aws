variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
}

variable "logs_bucket_id" {
  type        = string
  description = "S3 bucket name for CloudTrail log delivery"
}

variable "logs_bucket_arn" {
  type        = string
  description = "S3 bucket ARN (used in IAM policies)"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}

