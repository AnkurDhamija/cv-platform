output "bucket_name" {
  value = google_storage_bucket.cvs.name
}
output "artifact_registry_repo" {
  value = google_artifact_registry_repository.images.repository_id
}
