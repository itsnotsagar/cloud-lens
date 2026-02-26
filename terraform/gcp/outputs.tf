output "function_url" {
  description = "The URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.classify.url
}

output "function_name" {
  value = google_cloudfunctions2_function.classify.name
}

output "gcp_project_id" {
  value = var.gcp_project_id
}

output "gcp_region" {
  value = var.gcp_region
}
