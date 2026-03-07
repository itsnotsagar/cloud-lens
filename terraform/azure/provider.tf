terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    # resource_group_name and storage_account_name passed via -backend-config at init time
    resource_group_name = "imgclass-tf-state-rg"
    container_name      = "tfstate"
    key                 = "azure.tfstate"
  }

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
