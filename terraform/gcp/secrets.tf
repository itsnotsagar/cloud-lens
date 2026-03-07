# =============================================================================
# GCP Secret Manager - Centralized secrets storage
# =============================================================================

# Azure Communication Services connection string
resource "google_secret_manager_secret" "azure_email_connection_string" {
  secret_id = "${var.project_prefix}-azure-email-connection-string"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "azure_email_connection_string" {
  secret      = google_secret_manager_secret.azure_email_connection_string.id
  secret_data = var.azure_email_connection_string
}

# Azure sender address
resource "google_secret_manager_secret" "azure_sender_address" {
  secret_id = "${var.project_prefix}-azure-sender-address"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "azure_sender_address" {
  secret      = google_secret_manager_secret.azure_sender_address.id
  secret_data = var.azure_sender_address
}

# EventBridge authentication token for GCP Function access
resource "random_password" "eventbridge_auth_token" {
  length  = 64
  special = true
}

resource "google_secret_manager_secret" "eventbridge_auth_token" {
  secret_id = "${var.project_prefix}-eventbridge-auth-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "eventbridge_auth_token" {
  secret      = google_secret_manager_secret.eventbridge_auth_token.id
  secret_data = random_password.eventbridge_auth_token.result
}
