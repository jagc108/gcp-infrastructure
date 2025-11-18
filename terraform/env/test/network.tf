########################################
# Shared VPC host / service binding
########################################

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id

  depends_on = [
    google_project_service.host_compute
  ]
}

resource "google_compute_shared_vpc_service_project" "service" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = var.service_project_id
}

########################################
# VPC + subredes con módulo oficial
########################################

module "shared_vpc_network" {
  source  = "terraform-google-modules/network/google"
  version = "13.0.0"

  project_id   = var.host_project_id
  network_name = var.network_name
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name           = var.gke_subnet_name
      subnet_ip             = var.gke_subnet_ip_cidr
      subnet_region         = var.region
      subnet_private_access = tostring(var.gke_subnet_private_ip_google_access)
    },
    {
      subnet_name           = var.internal_subnet_1_name
      subnet_ip             = var.internal_subnet_1_ip_cidr
      subnet_region         = var.region
      subnet_private_access = tostring(var.internal_subnet_1_private_ip_google_access)
    },
    {
      subnet_name           = var.internal_subnet_2_name
      subnet_ip             = var.internal_subnet_2_ip_cidr
      subnet_region         = var.region
      subnet_private_access = tostring(var.internal_subnet_2_private_ip_google_access)
    },
  ]

  secondary_ranges = {
    (var.gke_subnet_name) = [
      {
        range_name    = var.gke_pods_secondary_range_name
        ip_cidr_range = var.gke_pods_secondary_range_cidr
      },
      {
        range_name    = var.gke_services_secondary_range_name
        ip_cidr_range = var.gke_services_secondary_range_cidr
      }
    ]
  }

  depends_on = [
    google_project_service.host_compute
  ]
}

########################################
# Cloud Router + Cloud NAT con módulo oficial
########################################

module "cloud_router_nat" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "8.0.0"

  name       = var.cloud_router_name
  project_id = var.host_project_id
  region     = var.region
  network    = module.shared_vpc_network.network_name

  bgp = {
    asn = tostring(var.cloud_router_bgp_asn)
  }

  nats = [
    {
      name                               = var.cloud_nat_name
      nat_ip_allocate_option             = var.cloud_nat_ip_allocate_option
      source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

      log_config = {
        enable = var.cloud_nat_log_enable
        filter = var.cloud_nat_log_filter
      }
    }
  ]

  depends_on = [
    google_project_service.host_compute
  ]
  
}