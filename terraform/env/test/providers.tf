# Host project = donde vive la Shared VPC
provider "google" {
  project = var.host_project_id
  region  = var.region
}

# Service project = donde vive el cluster GKE
provider "google" {
  alias   = "service"
  project = var.service_project_id
  region  = var.region
}