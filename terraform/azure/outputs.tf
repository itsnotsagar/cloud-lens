output "communication_service_name" {
  description = "Name of the Communication Service"
  value       = azurerm_communication_service.main.name
}

output "email_service_name" {
  description = "Name of the Email Communication Service"
  value       = azurerm_email_communication_service.main.name
}

output "sender_domain" {
  description = "The Azure-managed sender domain"
  value       = azurerm_email_communication_service_domain.main.from_sender_domain
}

output "sender_address" {
  description = "The full sender email address"
  value       = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
}

output "communication_service_connection_string" {
  description = "Connection string for Azure Communication Services (sensitive)"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "notification_email" {
  description = "Notification email address"
  value       = var.notification_email
}
