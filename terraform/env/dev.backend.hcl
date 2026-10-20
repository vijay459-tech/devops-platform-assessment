# Remote state: one bucket per environment (in that environment's project), versioned,
# with native GCS state locking. Placeholders; create the bucket out-of-band (docs/terraform.md).
bucket = "example-dev-project-tfstate"
prefix = "cloud-run/demo-api"
