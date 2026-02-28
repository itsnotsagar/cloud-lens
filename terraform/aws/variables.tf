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

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "gcp_function_url" {
  description = "URL of the GCP Cloud Function (from GCP module output)"
  type        = string
}

variable "eventbridge_auth_token" {
  description = "Authentication token for EventBridge to invoke GCP function"
  type        = string
  sensitive   = true
}
