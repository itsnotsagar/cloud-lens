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

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}
