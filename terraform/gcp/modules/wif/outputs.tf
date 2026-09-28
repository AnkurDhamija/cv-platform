output "wif_provider" {
  description = "Value for the GH Actions 'workload_identity_provider' input."
  value       = google_iam_workload_identity_pool_provider.github.name
}
output "ci_deployer_sa" {
  value = google_service_account.deployer.email
}
