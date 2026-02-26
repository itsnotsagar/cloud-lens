variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "imgclass"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# From aws-core outputs
variable "image_bucket_name" {
  description = "Name of the S3 image bucket"
  type        = string
}

variable "image_bucket_arn" {
  description = "ARN of the S3 image bucket"
  type        = string
}

# From gcp outputs
variable "gcp_function_url" {
  description = "URL of the GCP Cloud Function to relay events to"
  type        = string
}
