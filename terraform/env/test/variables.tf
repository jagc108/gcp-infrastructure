variable "host_project_id" {
  description = "ID del proyecto host (Shared VPC)"
  type        = string
}

variable "service_project_id" {
  description = "ID del proyecto service donde corre GKE"
  type        = string
}

variable "region" {
  description = "Región para red y GKE"
  type        = string
  default     = "us-central1"
}