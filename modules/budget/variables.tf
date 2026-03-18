variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
}

variable "alert_email" {
  type        = string
  description = "Email address to receive budget alerts"
}

variable "budget_limit" {
  type        = number
  description = "Monthly budget limit in USD"
  default     = 50
}
