# Selects the AWS region where the infrastructure is provisioned.
variable "aws_region" {
  type        = string
  description = "Deployment region; only used during separately approved AWS work."
  default     = "us-east-1"
}

# Restricts Terraform operations to the intended AWS account.
variable "aws_account_id" {
  type        = string
  description = "Expected AWS account; prevents an approved plan from targeting another account."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Use the intended 12-digit AWS account ID."
  }
}

# Adds the environment suffix to resource names and tags.
variable "environment" {
  type        = string
  default     = "dev"
  description = "Short lowercase environment suffix for all resource names."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "Environment must start with a lowercase letter and contain at most 16 lowercase letters, digits, or hyphens."
  }
}

# Selects the two Availability Zones used by the network and workloads.
variable "availability_zones" {
  type        = list(string)
  description = "Exactly two AZs in the selected region; verify account availability before deployment."
  default     = ["us-east-1a", "us-east-1b"]
  validation {
    condition = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2 && alltrue([
      for zone in var.availability_zones : startswith(zone, var.aws_region)
    ])
    error_message = "Supply two distinct availability zones in aws_region."
  }
}

# Selects the EKS Kubernetes control-plane version.
variable "kubernetes_version" {
  type        = string
  description = "Explicit EKS version. Choose one in standard support at the AWS deployment review."
  validation {
    condition     = can(regex("^1[.][0-9]+$", var.kubernetes_version))
    error_message = "Use an explicit Kubernetes version such as 1.35; its availability must be reviewed before AWS work."
  }
}

# Identifies the existing IAM principal granted EKS administrator access.
variable "cluster_admin_principal_arn" {
  type        = string
  description = "Existing administrator IAM user or role ARN, not root or an STS session ARN."
  validation {
    condition     = can(regex("^arn:aws:iam::${var.aws_account_id}:(user|role)/.+$", var.cluster_admin_principal_arn))
    error_message = "Use an existing IAM user or role ARN in the intended AWS account; root and STS session ARNs are not EKS access-entry principals."
  }
}

# Restricts public access to the EKS Kubernetes API endpoint.
variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "Explicit administrator/CI public IPv4 CIDRs for EKS API access. No all-internet access."
  validation {
    condition = length(var.eks_public_access_cidrs) > 0 && alltrue([
      for cidr in var.eks_public_access_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Supply explicit IPv4 CIDRs of /24 or narrower; use your administrator egress /32 where possible."
  }
}

# Selects the EC2 instance type for the managed EKS worker group.
variable "node_instance_type" {
  type        = string
  default     = "t3.xlarge"
  description = "Single x86 worker sized for APIs, Kafka, ZooKeeper, and observability in the demo."
}

# Selects the RDS PostgreSQL instance class.
variable "db_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "Small development PostgreSQL instance, not a production sizing recommendation."
}

# Sets the globally unique private S3 bucket name for covers and analytics files.
variable "cover_bucket_name" {
  type        = string
  description = "Globally unique, private cover bucket name."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.cover_bucket_name))
    error_message = "Use 3-63 lowercase letters, numbers, and hyphens, starting/ending with a letter or number."
  }
}

# Enables deletion protection for persistent database and table resources.
variable "protect_data" {
  type        = bool
  default     = true
  description = "Deletion protection for RDS and DynamoDB. Changing this is a separately approved cloud mutation."
}

# Controls whether Terraform creates the optional EMR analytics cluster.
variable "enable_analytics_cluster" {
  type        = bool
  default     = true
  description = "Keeps the assignment Flink cluster enabled; set false only in a reviewed cleanup plan."
}

# Controls whether the EMR analytics cluster is protected from termination.
variable "emr_termination_protection" {
  type        = bool
  default     = true
  description = "Preserves the existing EMR protection; disable only in an approved cleanup plan."
}

# Sets the verified SES sender address used by notification delivery.
variable "ses_sender" {
  type        = string
  description = "Verified SES sender identity used by the notification Lambda."
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.ses_sender))
    error_message = "Supply a verified email address for SES."
  }
}
