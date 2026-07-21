# Root module — wires every component together.
# Each module owns one concern; outputs from one feed inputs to the next.

provider "aws" {
  region = var.region
}

# Tags applied to every taggable resource across all modules
locals {
  tags = {
    Project   = var.project_name
    Purpose   = "detection-lab"
    ManagedBy = "terraform"
  }
}

# S3 bucket for CloudTrail log delivery
module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  tags         = local.tags
}

# VPC, subnet, IGW, security group, and VPC Flow Logs
module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  log_retention_days = var.log_retention_days
  tags               = local.tags
}

# CloudTrail trail → S3 + CloudWatch, plus metric filters
module "cloudtrail" {
  source = "./modules/cloudtrail"

  project_name       = var.project_name
  logs_bucket_id     = module.storage.bucket_id
  logs_bucket_arn    = module.storage.bucket_arn
  log_retention_days = var.log_retention_days
  tags               = local.tags
}

# GuardDuty detector + HIGH/CRITICAL finding alerts via EventBridge → SNS
module "guardduty" {
  source = "./modules/guardduty"

  project_name = var.project_name
  region       = var.region
  alert_email  = var.alert_email
  tags         = local.tags
}

# Monthly spend guardrail with email alerts at 80% and 100%
module "budget" {
  source = "./modules/budget"

  project_name = var.project_name
  alert_email  = var.alert_email
  budget_limit = var.budget_limit
}

# Linux VM with IAM instance profile, CloudWatch Agent, auditd, and Stratus Red Team
module "ec2" {
  source = "./modules/ec2"

  project_name       = var.project_name
  region             = var.region
  subnet_id          = module.networking.subnet_id
  security_group_id  = module.networking.security_group_id
  auto_shutdown_hour = var.auto_shutdown_hour
  log_retention_days = var.log_retention_days
  tags               = local.tags
}
