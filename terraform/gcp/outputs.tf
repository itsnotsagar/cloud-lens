output "function_url" {
  description = "The URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.classify.url
}

output "function_name" {
  description = "Name of the Cloud Function"
  value       = google_cloudfunctions2_function.classify.name
}

output "gcp_project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "eventbridge_auth_token" {
  description = "EventBridge authentication token (sensitive)"
  value       = random_password.eventbridge_auth_token.result
  sensitive   = true
}

output "service_account_unique_id" {
  description = "Unique ID of the Cloud Function service account (for AWS OIDC federation)"
  value       = google_service_account.function.unique_id
}

output "azure_email_connection_string_secret_id" {
  description = "Secret Manager ID for Azure email connection string"
  value       = google_secret_manager_secret.azure_email_connection_string.id
}

output "azure_sender_address_secret_id" {
  description = "Secret Manager ID for Azure sender address"
  value       = google_secret_manager_secret.azure_sender_address.id
}

output "eventbridge_auth_token_secret_id" {
  description = "Secret Manager ID for EventBridge auth token"
  value       = google_secret_manager_secret.eventbridge_auth_token.id
}
