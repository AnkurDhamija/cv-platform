# =============================================================================
# Root composition: wires the independent modules together. Everything that
# differs per environment comes from -var-file=environments/<env>.tfvars.
# =============================================================================
module "network" {
  source = "./modules/network"
  name   = local.name
  region = var.region
}

module "gke" {
  source                 = "./modules/gke"
  name                   = local.name
  region                 = var.region
  project_id             = var.project_id
  network_id             = module.network.network_id
  subnet_id              = module.network.subnet_id
  pods_range_name        = module.network.pods_range_name
  services_range_name    = module.network.services_range_name
  node_count             = var.node_count
  min_node_count         = var.min_node_count
  max_node_count         = var.max_node_count
  deletion_protection    = var.deletion_protection
  machine_type           = var.machine_type
  disk_size_gb           = var.disk_size_gb
  release_channel        = var.release_channel
  master_authorized_cidr = var.master_authorized_cidr
  labels                 = local.labels
  node_locations         = var.node_locations
}

module "storage" {
  source         = "./modules/storage"
  name           = local.name
  region         = var.region
  cv_bucket_name = var.cv_bucket_name
  labels         = local.labels
}

module "iam" {
  source      = "./modules/iam"
  project_id  = var.project_id
  bucket_name = module.storage.bucket_name
  suffix      = local.suffix
  depends_on  = [module.gke]
}

module "wif" {
  source      = "./modules/wif"
  project_id  = var.project_id
  github_repo = var.github_repo
  suffix      = local.suffix
}
