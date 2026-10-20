# Plan-level tests with a mocked provider: no credentials, no network, no cost.
# Run: terraform -chdir=terraform/modules/cloud_run_service init -backend=false && \
#      terraform -chdir=terraform/modules/cloud_run_service test

mock_provider "google" {}

variables {
  project_id   = "example-test-project"
  region       = "us-central1"
  environment  = "dev"
  service_name = "demo-api"
  image        = "us-central1-docker.pkg.dev/example-test-project/apps/demo-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "Default ingress must restrict direct internet access (internal + load balancer only)."
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "No invoker may be granted by default; access must be an explicit, reviewed decision."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.deletion_protection == true
    error_message = "Deletion protection must default to true."
  }

  assert {
    condition     = google_service_account.runtime.account_id == "demo-api-dev-run"
    error_message = "A dedicated, predictably named runtime service account must be created."
  }
}

run "naming_and_labels" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.name == "demo-api-dev"
    error_message = "Service name must be <service_name>-<environment>."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.labels["environment"] == "dev" && google_cloud_run_v2_service.this.labels["managed-by"] == "terraform"
    error_message = "environment and managed-by labels must be applied."
  }
}

run "sizing_is_configurable" {
  command = plan

  variables {
    cpu             = "2"
    memory          = "1Gi"
    timeout_seconds = 120
    max_concurrency = 40
    min_instances   = 1
    max_instances   = 10
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].timeout == "120s"
    error_message = "timeout_seconds must map to the revision timeout."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].max_instance_request_concurrency == 40
    error_message = "max_concurrency must map to per-instance request concurrency."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].scaling[0].min_instance_count == 1 && google_cloud_run_v2_service.this.template[0].scaling[0].max_instance_count == 10
    error_message = "min/max instances must map to scaling settings."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].resources[0].limits["memory"] == "1Gi" && google_cloud_run_v2_service.this.template[0].containers[0].resources[0].limits["cpu"] == "2"
    error_message = "cpu and memory must map to container limits."
  }
}

run "image_is_deployed_by_digest" {
  command = plan

  assert {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", google_cloud_run_v2_service.this.template[0].containers[0].image))
    error_message = "The deployed image must be referenced by immutable digest."
  }
}

run "authenticated_invoker_is_granted_only_when_named" {
  command = plan

  variables {
    invoker_members = ["serviceAccount:caller@example-test-project.iam.gserviceaccount.com"]
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 1
    error_message = "Exactly the named invoker should be granted."
  }

  assert {
    condition     = alltrue([for k, v in google_cloud_run_v2_service_iam_member.invoker : v.role == "roles/run.invoker"])
    error_message = "Invokers must only receive roles/run.invoker."
  }
}

run "secrets_are_references_with_scoped_iam" {
  command = plan

  variables {
    secret_env = {
      API_TOKEN = { secret = "api-token", version = "3" }
      DB_PASS   = { secret = "db-password", version = "latest" }
    }
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.runtime_secret_access) == 2
    error_message = "Accessor must be granted per referenced secret (2 secrets => 2 bindings), not project-wide."
  }

  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret_iam_member.runtime_secret_access : v.role == "roles/secretmanager.secretAccessor"])
    error_message = "Only secretAccessor may be granted on secrets."
  }

  assert {
    condition     = one([for e in google_cloud_run_v2_service.this.template[0].containers[0].env : e.value_source[0].secret_key_ref[0].secret if e.name == "API_TOKEN"]) == "api-token"
    error_message = "Secret env vars must be Secret Manager references (value_source), never literal values."
  }
}

run "same_secret_used_twice_gets_one_binding" {
  command = plan

  variables {
    secret_env = {
      A = { secret = "shared", version = "1" }
      B = { secret = "shared", version = "2" }
    }
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.runtime_secret_access) == 1
    error_message = "IAM bindings must be de-duplicated per secret."
  }
}
