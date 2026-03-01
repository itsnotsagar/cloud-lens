# =============================================================================
# Service Account for Cloud Function
# =============================================================================

resource "google_service_account" "function" {
  account_id   = "${var.project_prefix}-function-sa"
  display_name = "Service Account for ${var.project_prefix} Cloud Function"
  description  = "Used by Cloud Function to access Secret Manager and Vertex AI"
}

# Grant Secret Manager access
resource "google_project_iam_member" "function_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.function.email}"
}

# Grant Vertex AI access
resource "google_project_iam_member" "function_vertex_ai" {
  project = var.gcp_project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function.email}"
}

# =============================================================================
# Service Account for EventBridge API Destination
# =============================================================================

# Note: We allow unauthenticated invocations on the function itself
# because Cloud Run's authentication doesn't work well with EventBridge API Destinations.
# Instead, we validate the X-Auth-Token header in the function code.

resource "google_service_account" "eventbridge_invoker" {
  account_id   = "${var.project_prefix}-eventbridge-sa"
  display_name = "Service Account for EventBridge to invoke Cloud Function"
  description  = "Used by AWS EventBridge API Destination to authenticate"
}

# Allow unauthenticated invocations (we handle auth in function code)
resource "google_cloud_run_v2_service_iam_member" "allow_unauthenticated" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloudfunctions2_function.classify.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
