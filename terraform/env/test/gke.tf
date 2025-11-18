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
  name       = "shared-vpc-gke"

  regional = true
  region   = var.region

  network            = module.shared_vpc_network.network_name
  network_project_id = var.host_project_id
  subnetwork         = "gke-subnet"

  ip_range_pods     = "gke-pods"
  ip_range_services = "gke-services"

  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = "172.16.0.0/28"

  master_authorized_networks = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  ]

  remove_default_node_pool = true

  node_pools = [
    {
      name         = "primary-nodes"
      machine_type = "e2-medium"
      min_count    = 3
      max_count    = 3
      autoscaling  = false
      auto_upgrade = true
      auto_repair  = true
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {
      env = "prod"
    }
  }

  node_pools_tags = {
    all = ["gke-node"]
  }
}