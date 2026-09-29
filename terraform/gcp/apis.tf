# =============================================================================
# Enable the GCP APIs this stack depends on so `terraform apply` succeeds on a
# clean project (idempotent on an existing one). disable_on_destroy = false so a
# destroy never tears APIs out from under other workloads in a shared project.
# =============================================================================
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}
