terraform {
  required_version = ">= 1.5.0"

  # Backend configured via -backend-config during terraform init
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
