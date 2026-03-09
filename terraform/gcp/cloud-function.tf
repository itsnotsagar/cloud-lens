# =============================================================================
# Cloud Function source code bucket
# =============================================================================

resource "google_storage_bucket" "function_source" {
  name          = "${var.project_prefix}-function-source-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

# Package the function source code as a zip
data "archive_file" "classify_function" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/classify-function"
  output_path = "${path.root}/.build/classify-function.zip"
  excludes    = ["__pycache__", "*.pyc", ".DS_Store"]
}

# Upload the zip to the source bucket
resource "google_storage_bucket_object" "classify_function" {
  name   = "classify-function-${data.archive_file.classify_function.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.classify_function.output_path
}

# =============================================================================
# Cloud Function (2nd gen) — Image Classification
# =============================================================================

resource "google_cloudfunctions2_function" "classify" {
  name     = "${var.project_prefix}-classify"
  location = var.gcp_region

  build_config {
    runtime     = "python311"
    entry_point = "classify_image"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.classify_function.name
      }
    }
  }

  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512Mi" # vertexai + boto3 + secretmanager need headroom for cold starts
    timeout_seconds                  = 300     # S3 download + Gemini inference + email send
    max_instance_request_concurrency = 10      # I/O-bound work, safe to handle multiple requests per instance

    # Service-to-service authentication required
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account with Secret Manager access
    service_account_email = google_service_account.function.email

    environment_variables = {
      S3_BUCKET_NAME             = var.s3_bucket_name
      AWS_REGION                 = var.aws_region
      AWS_ROLE_ARN               = var.aws_role_arn
      NOTIFICATION_EMAIL         = var.notification_email
      GCP_PROJECT_ID             = var.gcp_project_id
      GCP_LOCATION               = var.gcp_region
      AUTH_TOKEN_SECRET_ID       = google_secret_manager_secret.eventbridge_auth_token.secret_id
      AZURE_EMAIL_CONN_SECRET_ID = google_secret_manager_secret.azure_email_connection_string.secret_id
      AZURE_SENDER_SECRET_ID     = google_secret_manager_secret.azure_sender_address.secret_id
    }
  }
}
