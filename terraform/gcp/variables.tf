variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "imgclass"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket where images are uploaded (from AWS module)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where S3 bucket lives"
  type        = string
  default     = "us-east-1"
}

variable "aws_role_arn" {
  description = "ARN of the AWS IAM role for S3 access via Workload Identity Federation"
  type        = string
}

variable "azure_email_connection_string" {
  description = "Azure Communication Services connection string (from Azure module)"
  type        = string
  sensitive   = true
}

variable "azure_sender_address" {
  description = "Azure Communication Services sender email address (from Azure module)"
  type        = string
}

variable "notification_email" {
  description = "Recipient email address for classification results"
  type        = string
}
