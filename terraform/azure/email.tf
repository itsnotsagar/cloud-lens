# =============================================================================
# Azure Communication Services — Email
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = "${var.project_prefix}-rg"
  location = var.azure_location

  tags = {
    Project = var.project_prefix
  }
}

# Communication Service instance
resource "azurerm_communication_service" "main" {
  name                = "${var.project_prefix}-comm"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = "United States"

  tags = {
    Project = var.project_prefix
  }
}

# Email Communication Service
resource "azurerm_email_communication_service" "main" {
  name                = "${var.project_prefix}-email"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = "United States"

  tags = {
    Project = var.project_prefix
  }
}

# Azure-managed domain (no custom DNS setup needed)
# Sends from: donotreply@<guid>.azurecomm.net
resource "azurerm_email_communication_service_domain" "main" {
  name             = "AzureManagedDomain"
  email_service_id = azurerm_email_communication_service.main.id

  domain_management = "AzureManaged"
}

# Link the email domain to the communication service
resource "azurerm_communication_service_email_domain_association" "main" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.main.id
}
