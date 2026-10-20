locals {
  full_name  = "${var.service_name}-${var.environment}"
  sa_id      = "${local.full_name}-run" # <= 25 chars given validation on service_name
  secret_ids = toset([for s in values(var.secret_env) : s.secret])

  labels = merge(var.labels, {
    environment = var.environment
    service     = var.service_name
    managed-by  = "terraform"
  })
}

# Dedicated runtime identity. The default compute service account is never used.
# It is granted nothing project-wide; see the IAM bindings below.
resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = local.sa_id
  display_name = "Cloud Run runtime: ${local.full_name}"
}

# Least privilege: accessor on each *referenced* secret only (not project-wide).
resource "google_secret_manager_secret_iam_member" "runtime_secret_access" {
  for_each = local.secret_ids

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  location            = var.region
  name                = local.full_name
  ingress             = var.ingress
  deletion_protection = var.deletion_protection
  labels              = local.labels

  template {
    service_account                  = google_service_account.runtime.email
    timeout                          = "${var.timeout_seconds}s"
    max_instance_request_concurrency = var.max_concurrency
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/ready"
        }
        initial_delay_seconds = 0
        period_seconds        = 3
        timeout_seconds       = 2
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/health"
        }
        period_seconds    = 10
        timeout_seconds   = 2
        failure_threshold = 3
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # The secret IAM must exist before a revision tries to mount the secret.
  depends_on = [google_secret_manager_secret_iam_member.runtime_secret_access]

  lifecycle {
    # Set by gcloud/console tooling; ignoring avoids perpetual diffs.
    ignore_changes = [client, client_version]
  }
}

# Authenticated callers only. Empty by default => no one can invoke.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
