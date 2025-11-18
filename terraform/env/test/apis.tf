############################
# Enable APIs in HOST PROJECT
############################

resource "google_project_service" "host_compute" {
  project = var.host_project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "host_iam" {
  project = var.host_project_id
  service = "iam.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "host_cloudresourcemanager" {
  project = var.host_project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = false
}

############################
# Enable APIs in SERVICE PROJECT
############################

resource "google_project_service" "service_compute" {
  project = var.service_project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "service_container" {
  project = var.service_project_id
  service = "container.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "service_iam" {
  project = var.service_project_id
  service = "iam.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "service_cloudresourcemanager" {
  project = var.service_project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = false
}