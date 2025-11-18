########################################
# Datos del service project
########################################

data "google_project" "service" {
  provider   = google.service
  project_id = var.service_project_id
}

locals {
  service_project_number = data.google_project.service.number

  # GKE service agent del service project
  #   service-<NUM>@container-engine-robot.iam.gserviceaccount.com
  gke_service_agent_sa = "service-${local.service_project_number}@container-engine-robot.iam.gserviceaccount.com"

  # Google APIs service account del service project
  #   <NUM>@cloudservices.gserviceaccount.com
  cloudservices_sa = "${local.service_project_number}@cloudservices.gserviceaccount.com"
}

########################################
# IAM bindings en el HOST PROJECT
########################################

# 1) GKE service agent -> puede USAR la red (Shared VPC) del host
resource "google_project_iam_member" "host_network_user_for_gke_sa" {
  project = var.host_project_id
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.gke_service_agent_sa}"
}

# 2) GKE service agent -> puede gestionar recursos de red compartidos
#    del host para el cluster (Host Service Agent User)
resource "google_project_iam_member" "host_service_agent_user_for_gke_sa" {
  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:${local.gke_service_agent_sa}"
}

# 3) Google APIs service account -> también puede usar la red del host
resource "google_project_iam_member" "host_network_user_for_cloudservices_sa" {
  project = var.host_project_id
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.cloudservices_sa}"
}