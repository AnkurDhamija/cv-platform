variable "name" {
  type = string
}
variable "region" {
  type = string
}
variable "project_id" {
  type = string
}
variable "network_id" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "pods_range_name" {
  type = string
}
variable "services_range_name" {
  type = string
}
variable "node_count" {
  type    = number
  default = 2
}
variable "master_authorized_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
variable "labels" {
  type    = map(string)
  default = {}
}

variable "deletion_protection" {
  type    = bool
  default = false
}
variable "min_node_count" {
  type    = number
  default = 1
}
variable "max_node_count" {
  type    = number
  default = 3
}
variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}
variable "disk_size_gb" {
  type    = number
  default = 50
}
variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "node_locations" {
  type    = list(string)
  default = []
}
