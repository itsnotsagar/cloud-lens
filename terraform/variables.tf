# Root variables shared across modules
# These are referenced in terraform.tfvars.example

# Project-wide
variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "imgclass"
}

variable "notification_email" {
  description = "Email address to receive classification results"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

# AWS
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# GCP
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

# Azure
variable "azure_location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus"
}
