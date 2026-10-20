output "service_name" {
  description = "Cloud Run service name."
  value       = google_cloud_run_v2_service.this.name
}

output "service_url" {
  description = "Default run.app URL. Reachable by internet callers only if ingress allows it."
  value       = google_cloud_run_v2_service.this.uri
}

output "latest_ready_revision" {
  description = "Name of the latest ready revision. Record this as deployment evidence / rollback target."
  value       = google_cloud_run_v2_service.this.latest_ready_revision
}

output "runtime_service_account_email" {
  description = "Runtime identity of the service."
  value       = google_service_account.runtime.email
}

output "deployed_image" {
  description = "Image digest reference this configuration deploys."
  value       = var.image
}

output "ingress" {
  description = "Effective ingress setting."
  value       = google_cloud_run_v2_service.this.ingress
}
