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

variable "deletion_protection" {
  type        = bool
  description = "Protect the GKE cluster from accidental terraform destroy (set true in prod)."
  default     = false
}
variable "min_node_count" {
  type        = number
  description = "Minimum nodes for the GKE node pool autoscaler."
  default     = 1
}
variable "max_node_count" {
  type        = number
  description = "Maximum nodes for the GKE node pool autoscaler."
  default     = 3
}
variable "machine_type" {
  type        = string
  description = "GKE node machine type."
  default     = "e2-standard-2"
}
variable "disk_size_gb" {
  type        = number
  description = "GKE node boot disk size (GB)."
  default     = 50
}
variable "release_channel" {
  type        = string
  description = "GKE release channel: RAPID | REGULAR | STABLE."
  default     = "REGULAR"
}

variable "node_locations" {
  type    = list(string)
  default = []
}
