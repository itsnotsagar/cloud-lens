# =============================================================================
# Cloud Function source code bucket
# =============================================================================

resource "google_storage_bucket" "function_source" {
  name          = "${var.project_prefix}-function-source-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
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
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "256Mi"  # Reduced from 512Mi - sufficient for this workload
    timeout_seconds    = 60       # Reduced from 120s - typical execution is ~10-15s
    max_instance_request_concurrency = 1  # Process one request at a time per instance
    
    # Allow unauthenticated invocations (we handle auth in the function code)
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account with Secret Manager access
    service_account_email = google_service_account.function.email

    environment_variables = {
      S3_BUCKET_NAME      = var.s3_bucket_name
      AWS_REGION          = var.aws_region
      NOTIFICATION_EMAIL  = var.notification_email
      GCP_PROJECT_ID      = var.gcp_project_id
      GCP_LOCATION        = var.gcp_region
      EXPECTED_AUTH_TOKEN = random_password.eventbridge_auth_token.result
    }
  }
}
