############################
# Projects and region
############################

variable "host_project_id" {
  description = "ID of the host project (Shared VPC project)"
  type        = string
}

variable "service_project_id" {
  description = "ID of the service project where GKE runs"
  type        = string
}

variable "region" {
  description = "Region for the network and GKE cluster"
  type        = string
  default     = "us-central1"
}

############################
# VPC / Subnets
############################

variable "network_name" {
  description = "Name of the Shared VPC network"
  type        = string
  default     = "shared-vpc-network"
}

# GKE subnet
variable "gke_subnet_name" {
  description = "Name of the subnet for GKE"
  type        = string
  default     = "gke-subnet"
}

variable "gke_subnet_ip_cidr" {
  description = "CIDR range of the GKE subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "gke_subnet_private_ip_google_access" {
  description = "Enable Private Google Access on the GKE subnet"
  type        = bool
  default     = true
}

# Internal subnet 1
variable "internal_subnet_1_name" {
  description = "Name of the first internal subnet"
  type        = string
  default     = "internal-subnet-1"
}

variable "internal_subnet_1_ip_cidr" {
  description = "CIDR range of the first internal subnet"
  type        = string
  default     = "10.3.0.0/20"
}

variable "internal_subnet_1_private_ip_google_access" {
  description = "Enable Private Google Access on the first internal subnet"
  type        = bool
  default     = true
}

# Internal subnet 2
variable "internal_subnet_2_name" {
  description = "Name of the second internal subnet"
  type        = string
  default     = "internal-subnet-2"
}

variable "internal_subnet_2_ip_cidr" {
  description = "CIDR range of the second internal subnet"
  type        = string
  default     = "10.4.0.0/20"
}

variable "internal_subnet_2_private_ip_google_access" {
  description = "Enable Private Google Access on the second internal subnet"
  type        = bool
  default     = true
}

############################
# GKE secondary ranges
############################

variable "gke_pods_secondary_range_name" {
  description = "Name of the secondary IP range used for Pods"
  type        = string
  default     = "gke-pods"
}

variable "gke_pods_secondary_range_cidr" {
  description = "CIDR of the secondary IP range used for Pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "gke_services_secondary_range_name" {
  description = "Name of the secondary IP range used for Services"
  type        = string
  default     = "gke-services"
}

variable "gke_services_secondary_range_cidr" {
  description = "CIDR of the secondary IP range used for Services"
  type        = string
  default     = "10.2.0.0/20"
}

############################
# Cloud Router / NAT
############################

variable "cloud_router_name" {
  description = "Name of the Cloud Router"
  type        = string
  default     = "shared-vpc-nat-router"
}

variable "cloud_router_bgp_asn" {
  description = "BGP ASN for the Cloud Router"
  type        = number
  default     = 65001
}

variable "cloud_nat_name" {
  description = "Name of the Cloud NAT"
  type        = string
  default     = "shared-vpc-nat"
}

variable "cloud_nat_ip_allocate_option" {
  description = "NAT IP allocation mode (AUTO_ONLY or MANUAL_ONLY)"
  type        = string
  default     = "AUTO_ONLY"
}

variable "cloud_nat_log_enable" {
  description = "Enable logging for Cloud NAT"
  type        = bool
  default     = true
}

variable "cloud_nat_log_filter" {
  description = "Logging filter for Cloud NAT (ALL, ERRORS_ONLY, TRANSLATIONS_ONLY)"
  type        = string
  default     = "ERRORS_ONLY"
}

############################
# GKE cluster
############################

variable "gke_cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "shared-vpc-gke"
}

variable "gke_regional" {
  description = "Whether the cluster is regional (true) or zonal (false)"
  type        = bool
  default     = true
}

variable "gke_release_channel" {
  description = "GKE release channel (RAPID, REGULAR, STABLE)"
  type        = string
  default     = "REGULAR"
}

variable "gke_enable_private_nodes" {
  description = "Enable private nodes (no public IPs on nodes)"
  type        = bool
  default     = true
}

variable "gke_enable_private_endpoint" {
  description = "Enable private endpoint for the control plane"
  type        = bool
  default     = false
}

variable "gke_master_ipv4_cidr_block" {
  description = "CIDR block for the master internal range in a private cluster"
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the control plane"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  ]
}

############################
# GKE node pools
############################

variable "gke_node_pools" {
  description = "List of node pools for the GKE cluster"
  type = list(object({
    name         = string
    machine_type = string
    min_count    = number
    max_count    = number
    autoscaling  = bool
    auto_upgrade = bool
    auto_repair  = bool
  }))

  default = [
    {
      name         = "primary-nodes"
      machine_type = "e2-micro" # smallest/cheapest example
      min_count    = 3
      max_count    = 3
      autoscaling  = false
      auto_upgrade = true
      auto_repair  = true
    }
  ]
}

variable "gke_node_pools_oauth_scopes" {
  description = "OAuth scopes per group for the node pools"
  type        = map(list(string))
  default = {
    all = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

variable "gke_node_pools_labels" {
  description = "Labels per group for the node pools"
  type        = map(map(string))
  default = {
    all = {
      env = "prod"
    }
  }
}

variable "gke_node_pools_tags" {
  description = "Network tags per group for the node pools"
  type        = map(list(string))
  default = {
    all = ["gke-node"]
  }
}