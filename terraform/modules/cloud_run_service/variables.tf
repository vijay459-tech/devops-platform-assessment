variable "project_id" {
  description = "GCP project that hosts the service. Never hardcoded; supplied per environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project id (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "region" {
  description = "Cloud Run region, e.g. us-central1."
  type        = string
}

variable "environment" {
  description = "Deployment environment. Used in names and labels."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "service_name" {
  description = "Base service name (3-16 chars). The Cloud Run service is named <service_name>-<environment>."
  type        = string
  validation {
    # 16 chars max keeps "<name>-<env>-run" within the 30-char service account id limit.
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-16 chars: lowercase letters, digits, hyphens; start with a letter; not end with a hyphen."
  }
}

variable "image" {
  description = "Container image pinned by digest (registry/path@sha256:...). Tags are rejected so every deploy is traceable and promotable as the same artifact."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9.-]+-docker\\.pkg\\.dev/[^@\\s]+@sha256:[a-f0-9]{64}$", var.image))
    error_message = "image must be an Artifact Registry reference pinned by digest: REGION-docker.pkg.dev/PROJECT/REPO/NAME@sha256:<64 hex>."
  }
}

variable "cpu" {
  description = "CPU limit per instance (Cloud Run string form, e.g. \"1\", \"2\", \"1000m\")."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance, e.g. \"512Mi\", \"1Gi\"."
  type        = string
  default     = "512Mi"
}

variable "timeout_seconds" {
  description = "Per-request timeout in seconds (1-3600)."
  type        = number
  default     = 30
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "timeout_seconds must be between 1 and 3600."
  }
}

variable "max_concurrency" {
  description = "Maximum concurrent requests per instance (1-1000)."
  type        = number
  default     = 80
  validation {
    condition     = var.max_concurrency >= 1 && var.max_concurrency <= 1000
    error_message = "max_concurrency must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum instances kept warm. 0 allows scale-to-zero (cold starts); >0 costs money but reduces latency."
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0
    error_message = "min_instances must be >= 0."
  }
}

variable "max_instances" {
  description = "Maximum instances. Acts as a cost and downstream-protection ceiling."
  type        = number
  default     = 3
  validation {
    condition     = var.max_instances >= 1
    error_message = "max_instances must be >= 1."
  }
}

variable "ingress" {
  description = <<-EOT
    Cloud Run ingress setting. Default INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER blocks the
    *.run.app URL for internet callers so that the only public path is a load balancer
    (with Cloud Armor) once one exists. Use INGRESS_TRAFFIC_ALL only where direct,
    IAM-authenticated access is deliberately accepted (see docs/terraform.md).
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "ingress must be INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "invoker_members" {
  description = <<-EOT
    IAM members granted roles/run.invoker (authenticated access only). Empty by default:
    nobody can invoke until a caller identity is named. Public access (allUsers /
    allAuthenticatedUsers) is rejected by validation; make that a separate, reviewed change.
  EOT
  type        = list(string)
  default     = []
  validation {
    condition     = !anytrue([for m in var.invoker_members : contains(["allUsers", "allAuthenticatedUsers"], m)])
    error_message = "Public invokers (allUsers / allAuthenticatedUsers) are not permitted by this module."
  }
  validation {
    condition     = alltrue([for m in var.invoker_members : can(regex("^(user|group|serviceAccount|domain):", m))])
    error_message = "Each invoker member must be prefixed with user:, group:, serviceAccount: or domain:."
  }
}

variable "env_vars" {
  description = "Plain, non-secret environment variables. Never put secret values here."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = <<-EOT
    Environment variables sourced from Secret Manager. Map of ENV_VAR_NAME => { secret, version }.
    Only references are stored here, never values. `secret` is the secret id in this project;
    `version` is explicit ("3") or "latest". Prefer a pinned version in prod so a rotated
    secret does not change behaviour without a deploy.
  EOT
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}

variable "labels" {
  description = "Extra labels merged onto the service."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Block terraform destroy of the Cloud Run service. Leave true outside throwaway environments."
  type        = bool
  default     = true
}
