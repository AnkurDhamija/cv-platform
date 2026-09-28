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

variable "node_locations" {
  type    = list(string)
  default = []
}
