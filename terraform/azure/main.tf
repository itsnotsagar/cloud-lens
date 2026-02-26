terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "imgclass-tf-state-rg"
    storage_account_name = "imgclasstfstate"
    container_name       = "tfstate"
    key                  = "azure.tfstate"
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
