# Private, hardened GKE cluster with Workload Identity + Dataplane V2
# (Cilium NetworkPolicy enforcement). Shielded nodes, least-privilege node SA,
# auto node repair/upgrade, VPC flow logs (in the network module).
resource "google_container_cluster" "primary" {
  name     = var.name
  location = var.region

  network    = var.network_id
  subnetwork = var.subnet_id

  remove_default_node_pool = true
  initial_node_count       = 1
  networking_mode          = "VPC_NATIVE"
  datapath_provider        = "ADVANCED_DATAPATH"

  release_channel {
    channel = var.release_channel
  }

  resource_labels = var.labels

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.master_authorized_cidr
      display_name = "authorized"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  enable_shielded_nodes = true

  deletion_protection = var.deletion_protection
}

resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "GKE node service account (least privilege)"
}

resource "google_container_node_pool" "primary" {
  name    = "primary"
  cluster = google_container_cluster.primary.id
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

# A custom node service account gets NO roles by default. Grant the minimum the
# nodes need: pull images from Artifact Registry, and write logs/metrics.
resource "google_project_iam_member" "nodes_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
resource "google_project_iam_member" "nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
resource "google_project_iam_member" "nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
