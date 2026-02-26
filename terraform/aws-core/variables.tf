variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "imgclass"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}
