output "cluster_name" {
  value = module.gke.cluster_name
}
output "cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}
output "cv_bucket" {
  value = module.storage.bucket_name
}
output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${module.storage.artifact_registry_repo}"
}
output "cvproc_gsa_email" {
  value = module.iam.cvproc_gsa_email
}
output "public_api_gsa_email" {
  value = module.iam.pubapi_gsa_email
}
output "wif_provider" {
  description = "Value for the GH Actions 'workload_identity_provider' input."
  value       = module.wif.wif_provider
}
output "ci_deployer_sa" {
  value = module.wif.ci_deployer_sa
}
