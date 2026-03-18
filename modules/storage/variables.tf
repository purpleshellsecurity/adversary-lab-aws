variable "project_name" {
  type        = string
  description = "Prefix applied to all resource names"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
