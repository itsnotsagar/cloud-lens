terraform {
  required_version = ">= 1.5.0"

  # Backend configured via -backend-config during terraform init
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels = {
    project     = var.project_prefix
    environment = var.environment
    managed_by  = "terraform"
  }
}
