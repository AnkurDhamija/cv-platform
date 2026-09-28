variable "name" {
  type = string
}
variable "region" {
  type = string
}
variable "cv_bucket_name" {
  type = string
}
variable "labels" {
  type    = map(string)
  default = {}
}
