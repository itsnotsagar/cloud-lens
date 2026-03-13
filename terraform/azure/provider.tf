terraform {
  required_version = ">= 1.5.0"

  # Backend configured via -backend-config during terraform init (GitHub Actions)
  # For local development, uncomment and configure:
  # backend "azurerm" {
  #   resource_group_name  = "imgclass-tf-state-rg-<sub-short>"
  #   storage_account_name = "imgclasstf<sub-short>"
  #   container_name       = "tfstate"
  #   key                  = "azure.tfstate"
  # }
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
