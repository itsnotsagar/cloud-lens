terraform {
  required_version = ">= 1.5.0"

  # Backend configured via -backend-config during terraform init
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_prefix
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
