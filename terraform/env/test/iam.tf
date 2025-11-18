############################
# Service project info
############################

data "google_project" "service" {
  project_id = var.service_project_id
}

############################
# IAM for Shared VPC scenarios (host/service)
############################
# These bindings are only needed when using a separate host project
# for the Shared VPC. For sandbox/single-project (enable_shared_vpc = false),
# they are skipped to avoid errors and unnecessary IAM.

resource "google_project_iam_member" "host_network_user_for_gke_sa" {
  count   = var.enable_shared_vpc ? 1 : 0
  project = var.host_project_id
  role    = "roles/compute.networkUser"

  # GKE service agent in the SERVICE project
  member = "serviceAccount:service-${data.google_project.service.number}@container-engine-robot.iam.gserviceaccount.com"

  # Make sure container API is enabled before trying to grant roles to its service agent
  depends_on = [
    google_project_service.service_container
  ]
}

resource "google_project_iam_member" "host_service_agent_user_for_gke_sa" {
  count   = var.enable_shared_vpc ? 1 : 0
  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"

  member = "serviceAccount:service-${data.google_project.service.number}@container-engine-robot.iam.gserviceaccount.com"

  depends_on = [
    google_project_service.service_container
  ]
}

resource "google_project_iam_member" "host_network_user_for_cloudservices_sa" {
  count   = var.enable_shared_vpc ? 1 : 0
  project = var.host_project_id
  role    = "roles/compute.networkUser"

  # Cloud Services service account for the SERVICE project
  member = "serviceAccount:${data.google_project.service.number}@cloudservices.gserviceaccount.com"
}