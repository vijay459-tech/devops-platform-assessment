terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.30.0, < 8.7.1"
    }
  }

  # Partial configuration: bucket/prefix come from env/<environment>.backend.hcl
  # at `terraform init -backend-config=...`. Backends cannot use variables.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}
