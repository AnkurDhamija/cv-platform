# Workload Identity mapping — the core least-privilege control.
#   backend/cv-processor KSA -> cvproc GSA -> objectAdmin on the CV bucket
#   frontend/public-api  KSA -> pubapi GSA -> NO storage roles at all
# public-api therefore cannot read/write the bucket even if compromised.
resource "google_service_account" "cvproc" {
  account_id   = "cvproc-gsa${var.suffix}"
  display_name = "cv-processor (bucket read/write)"
}

resource "google_storage_bucket_iam_member" "cvproc_bucket" {
  bucket = var.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cvproc.email}"
}

resource "google_service_account_iam_member" "cvproc_wi" {
  service_account_id = google_service_account.cvproc.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[backend/cv-processor]"
}

# public-api: its own GSA with ZERO storage roles, to make the boundary explicit
# and auditable rather than relying on the absence of a binding.
resource "google_service_account" "pubapi" {
  account_id   = "pubapi-gsa${var.suffix}"
  display_name = "public-api (no storage access)"
}

resource "google_service_account_iam_member" "pubapi_wi" {
  service_account_id = google_service_account.pubapi.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[frontend/public-api]"
}
