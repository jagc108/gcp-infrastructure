########################################
# GKE privado en Shared VPC con módulo oficial
########################################

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  version = "41.0.2"

  providers = {
    google = google.service
  }

  project_id = var.service_project_id
  name       = var.gke_cluster_name

  regional = var.gke_regional
  region   = var.region

  network            = module.shared_vpc_network.network_name
  network_project_id = var.host_project_id
  subnetwork         = var.gke_subnet_name

  ip_range_pods     = var.gke_pods_secondary_range_name
  ip_range_services = var.gke_services_secondary_range_name

  enable_private_nodes    = var.gke_enable_private_nodes
  enable_private_endpoint = var.gke_enable_private_endpoint
  master_ipv4_cidr_block  = var.gke_master_ipv4_cidr_block

  release_channel = var.gke_release_channel

  master_authorized_networks = var.gke_master_authorized_networks

  remove_default_node_pool = true

  node_pools = var.gke_node_pools

  node_pools_oauth_scopes = var.gke_node_pools_oauth_scopes
  node_pools_labels       = var.gke_node_pools_labels
  node_pools_tags         = var.gke_node_pools_tags

  deletion_protection = var.gke_deletion_protection

  depends_on = [
    google_project_service.service_compute,
    google_project_service.service_container
  ]
}