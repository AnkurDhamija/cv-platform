variable "environment" {
  type        = string
  description = "Deployment environment: dev | test | prod. Drives per-env resource naming and state."
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "cluster_name" {
  type    = string
  default = "cv-platform"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo allowed to federate into GCP, as 'owner/repo'."
}

variable "cv_bucket_name" {
  type        = string
  description = "Globally-unique name for the CV object bucket."
}

variable "node_count" {
  type    = number
  default = 2
}

variable "master_authorized_cidr" {
  type        = string
  description = "CIDR permitted to reach the private cluster control plane."
  default     = "0.0.0.0/0"
}

variable "node_locations" {
  type    = list(string)
  default = []
}
