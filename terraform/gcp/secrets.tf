# =============================================================================
# GCP Secret Manager - Centralized secrets storage
# =============================================================================

# AWS Access Key ID for S3 access (restricted permissions)
resource "google_secret_manager_secret" "aws_access_key_id" {
  secret_id = "${var.project_prefix}-aws-access-key-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_access_key_id" {
  secret      = google_secret_manager_secret.aws_access_key_id.id
  secret_data = var.aws_access_key_id
}

# AWS Secret Access Key for S3 access (restricted permissions)
resource "google_secret_manager_secret" "aws_secret_access_key" {
  secret_id = "${var.project_prefix}-aws-secret-access-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_secret_access_key" {
  secret      = google_secret_manager_secret.aws_secret_access_key.id
  secret_data = var.aws_secret_access_key
}

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
