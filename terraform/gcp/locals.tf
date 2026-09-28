# Per-environment naming. ONE set of .tf files serves dev/test/prod; only the
# -var-file changes. `environment` is the single knob:
#   * dev  -> suffix "" so names match the originally-applied stack (no churn)
#   * test -> "-test", prod -> "-prod" (unique even in a shared project)
locals {
  suffix = var.environment == "dev" ? "" : "-${var.environment}"
  name   = "${var.cluster_name}${local.suffix}"

  labels = {
    app         = "cv-platform"
    environment = var.environment
    managed_by  = "terraform"
  }
}
