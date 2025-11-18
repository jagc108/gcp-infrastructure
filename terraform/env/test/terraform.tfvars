############################
# VPC / Subnets
############################

network_name = "shared-vpc-network"

# Subnet GKE
gke_subnet_name                     = "gke-subnet"
gke_subnet_ip_cidr                  = "10.0.0.0/20"
gke_subnet_private_ip_google_access = true

# Subnet interna 1
internal_subnet_1_name                     = "internal-subnet-1"
internal_subnet_1_ip_cidr                  = "10.3.0.0/20"
internal_subnet_1_private_ip_google_access = true

# Subnet interna 2
internal_subnet_2_name                     = "internal-subnet-2"
internal_subnet_2_ip_cidr                  = "10.4.0.0/20"
internal_subnet_2_private_ip_google_access = true

############################
# Rangos secundarios GKE
############################

gke_pods_secondary_range_name = "gke-pods"
gke_pods_secondary_range_cidr = "10.1.0.0/16"

gke_services_secondary_range_name = "gke-services"
gke_services_secondary_range_cidr = "10.2.0.0/20"

############################
# Cloud Router / NAT
############################

cloud_router_name    = "shared-vpc-nat-router"
cloud_router_bgp_asn = 65001

cloud_nat_name               = "shared-vpc-nat"
cloud_nat_ip_allocate_option = "AUTO_ONLY"
cloud_nat_log_enable         = true
cloud_nat_log_filter         = "ERRORS_ONLY"

############################
# GKE Cluster
############################

gke_cluster_name    = "shared-vpc-gke"
gke_regional        = true
gke_release_channel = "REGULAR"

gke_enable_private_nodes    = true
gke_enable_private_endpoint = false
gke_master_ipv4_cidr_block  = "172.16.0.0/28"

gke_master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all"
  }
]

############################
# GKE Node pools
############################

gke_node_pools = [
  {
    name         = "primary-nodes"
    machine_type = "e2-small"
    min_count    = 1
    max_count    = 3
    autoscaling  = false
    auto_upgrade = true
    auto_repair  = true
  }
]

gke_node_pools_oauth_scopes = {
  all = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}

gke_node_pools_labels = {
  all = {
    env = "test"
  }
}

gke_node_pools_tags = {
  all = ["gke-node"]
}