variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "imgclass"
}

variable "azure_location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "notification_email" {
  description = "Email address to receive classification results"
  type        = string
}
