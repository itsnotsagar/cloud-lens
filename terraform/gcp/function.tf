# =============================================================================
# Cloud Function source code bucket
# =============================================================================

resource "google_storage_bucket" "function_source" {
  name          = "${var.project_prefix}-function-source-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    project = var.project_prefix
  }
}

# Package the function source code as a zip
data "archive_file" "classify_function" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/classify-function"
  output_path = "${path.module}/../../.build/classify-function.zip"
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
    available_memory   = "512Mi"
    timeout_seconds    = 120

    environment_variables = {
      AWS_ACCESS_KEY_ID_VALUE     = var.aws_access_key_id
      AWS_SECRET_ACCESS_KEY_VALUE = var.aws_secret_access_key
      AWS_REGION_VALUE            = var.aws_region
      S3_BUCKET_NAME              = var.s3_bucket_name
      AZURE_EMAIL_CONNECTION_STR  = var.azure_email_connection_string
      AZURE_SENDER_ADDRESS        = var.azure_sender_address
      NOTIFICATION_EMAIL          = var.notification_email
      GCP_PROJECT_ID              = var.gcp_project_id
      GCP_LOCATION                = var.gcp_region
    }
  }

  labels = {
    project = var.project_prefix
  }
}

# Allow unauthenticated invocations (so Lambda relay can call without GCP creds)
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloudfunctions2_function.classify.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
