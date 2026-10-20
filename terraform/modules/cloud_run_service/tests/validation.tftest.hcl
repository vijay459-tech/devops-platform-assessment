# Negative tests: unsafe or malformed inputs must be rejected at plan time.

mock_provider "google" {}

variables {
  project_id   = "example-test-project"
  region       = "us-central1"
  environment  = "prod"
  service_name = "demo-api"
  image        = "us-central1-docker.pkg.dev/example-test-project/apps/demo-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

run "rejects_mutable_image_tag" {
  command = plan
  variables {
    image = "us-central1-docker.pkg.dev/example-test-project/apps/demo-api:latest"
  }
  expect_failures = [var.image]
}

run "rejects_public_invoker" {
  command = plan
  variables {
    invoker_members = ["allUsers"]
  }
  expect_failures = [var.invoker_members]
}

run "rejects_unprefixed_invoker" {
  command = plan
  variables {
    invoker_members = ["someone@example.com"]
  }
  expect_failures = [var.invoker_members]
}

run "rejects_unknown_environment" {
  command = plan
  variables {
    environment = "staging"
  }
  expect_failures = [var.environment]
}

run "rejects_overlong_service_name" {
  command = plan
  variables {
    service_name = "this-name-is-way-too-long"
  }
  expect_failures = [var.service_name]
}

run "rejects_invalid_ingress" {
  command = plan
  variables {
    ingress = "ANYTHING"
  }
  expect_failures = [var.ingress]
}
