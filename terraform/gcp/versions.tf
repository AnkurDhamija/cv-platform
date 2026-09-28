terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }
  # Remote state in GCS. Bucket + per-env prefix are supplied at init time via
  #   terraform init -backend-config=environments/<env>.gcs.tfbackend
  # so dev/test/prod keep isolated state in one bucket under distinct prefixes.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}
