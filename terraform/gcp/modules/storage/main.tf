# CV object bucket (GCS equivalent of local MinIO): versioned, public access
# blocked, 30-day lifecycle (GDPR retention), uniform bucket-level access.
resource "google_storage_bucket" "cvs" {
  name                        = var.cv_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = var.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Artifact Registry for signed container images.
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${var.name}-images"
  format        = "DOCKER"
  description   = "Signed CV platform images"
  labels        = var.labels
}
