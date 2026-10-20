terraform {
  required_version = ">= 1.7.0, < 2.0.0" # 1.7+ required for mock_provider in terraform test

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.30.0, < 7.0.0"
    }
  }
}
