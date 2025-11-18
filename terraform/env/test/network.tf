########################################
# Shared VPC host / service binding
########################################

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
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
  network_name = "shared-vpc-network"
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name           = "gke-subnet"
      subnet_ip             = "10.0.0.0/20"
      subnet_region         = var.region
      subnet_private_access = "true"
    },
    {
      subnet_name           = "internal-subnet-1"
      subnet_ip             = "10.3.0.0/20"
      subnet_region         = var.region
      subnet_private_access = "true"
    },
    {
      subnet_name           = "internal-subnet-2"
      subnet_ip             = "10.4.0.0/20"
      subnet_region         = var.region
      subnet_private_access = "true"
    },
  ]

  secondary_ranges = {
    "gke-subnet" = [
      {
        range_name    = "gke-pods"
        ip_cidr_range = "10.1.0.0/16"
      },
      {
        range_name    = "gke-services"
        ip_cidr_range = "10.2.0.0/20"
      }
    ]
  }
}

########################################
# Cloud Router + Cloud NAT con módulo oficial
########################################

module "cloud_router_nat" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "8.0.0"

  name       = "shared-vpc-nat-router"
  project_id = var.host_project_id
  region     = var.region
  network    = module.shared_vpc_network.network_name

  bgp = {
    asn = "65001"
  }

  nats = [
    {
      name                               = "shared-vpc-nat"
      nat_ip_allocate_option             = "AUTO_ONLY"
      source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

      log_config = {
        enable = true
        filter = "ERRORS_ONLY"
      }
    }
  ]
}