# AWS
output "aws_state_bucket" {
  value = aws_s3_bucket.terraform_state.id
}

output "aws_region" {
  value = var.aws_region
}

# GCP
output "gcp_state_bucket" {
  value = google_storage_bucket.terraform_state.name
}

# Azure
output "azure_state_resource_group" {
  value = azurerm_resource_group.terraform_state.name
}

output "azure_state_storage_account" {
  value = azurerm_storage_account.terraform_state.name
}

output "azure_state_container" {
  value = azurerm_storage_container.terraform_state.name
}
