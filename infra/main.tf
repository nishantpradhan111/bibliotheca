# Pins Terraform and the AWS/archive providers used to define the deployment.
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Configures AWS access, account safety checks, and common project tags.
# validate and mocked tests do not configure this provider against AWS.
# No backend is configured until the team agrees on state ownership.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      Project     = "digital-library"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Builds shared names and maps the selected Availability Zones to subnet indexes.
locals {
  name  = "digital-library-${var.environment}"
  zones = { for index, zone in var.availability_zones : zone => index }
}
