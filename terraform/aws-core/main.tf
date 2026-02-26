terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket  = "imgclass-tf-state-aws"
    key     = "aws-core/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
