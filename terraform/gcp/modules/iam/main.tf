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

# --- External Secrets Operator (ESO) ----------------------------------------
# GSA ESO uses to read DB credentials from Secret Manager over Workload Identity.
# The KSA that references it (backend/external-secrets) is created by the backend
# Helm chart; the ESO controller SA is external-secrets/external-secrets.
resource "google_service_account" "eso" {
  account_id   = "eso-gsa"
  display_name = "External Secrets Operator"
  project      = var.project_id
}

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_service_account_iam_member" "eso_wi_backend" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[backend/external-secrets]"
}

resource "google_service_account_iam_member" "eso_wi_controller" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

# DB credential CONTAINER only — the value (JSON username/password/dbname) is
# written out-of-band (gcloud/CI), never stored in tfstate.
resource "google_secret_manager_secret" "cv_db_credentials" {
  project   = var.project_id
  secret_id = "cv-db-credentials"
  replication {
    auto {}
  }
}
