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
# Allow unauthenticated invocations (auth handled by X-Auth-Token in app code)
# EventBridge API Destinations cannot present GCP identity tokens, so Cloud Run
# must allow the request through. The function validates X-Auth-Token via
# Secret Manager + hmac.compare_digest.
# =============================================================================

resource "google_cloud_run_v2_service_iam_member" "allow_unauthenticated" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloudfunctions2_function.classify.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
