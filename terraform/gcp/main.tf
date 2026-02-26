terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {
    bucket = "imgclass-tf-state-gcp"
    prefix = "gcp"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
