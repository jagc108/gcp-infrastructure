# GCP Shared VPC + GKE (Prod)

Terraform configuration to provision:

- A **Shared VPC** in a **host project** (optional, for corporate orgs)
- **3 subnets** (one for GKE with secondary ranges, two internal)
- **Cloud Router + Cloud NAT**
- A **private, VPC-native GKE Standard cluster** in a **service project** (or same project in sandbox)
- **IAM bindings** required for GKE + Shared VPC (when enabled)
- **Required GCP APIs enabled** in host and service projects
- **Remote state** stored in a GCS bucket
- **GitHub Actions** workflows for `terraform plan, apply & destroy` using **Workload Identity Federation (WIF)**

This repo is structured around `terraform/env/test`.

---

## Usage

From the repo root:

```bash
cd terraform/env/test

# Set required variables (example)
export TF_VAR_host_project_id="my-host-project"
export TF_VAR_service_project_id="my-service-project"
export TF_VAR_region="us-east1"

terraform init
terraform plan
terraform apply
```

Remote state is configured with a GCS backend in `backend.tf`.  
Make sure the bucket exists and the Terraform service account has access.

---

## Requirements

| Name        | Version              |
|-------------|----------------------|
| terraform   | >= 1.5.0             |
| google      | >= 7.0.0, < 8.0.0    |
| google-beta | >= 7.0.0, < 8.0.0    |

---

## Providers

| Name            | Version              | Description                        |
|-----------------|----------------------|------------------------------------|
| google          | >= 7.0.0, < 8.0.0    | Default provider (host project)    |
| google.service  | >= 7.0.0, < 8.0.0    | Aliased provider (service project) |

---

## Modules

| Name               | Source                                                     | Version  | Description                                  |
|--------------------|------------------------------------------------------------|----------|----------------------------------------------|
| shared_vpc_network | terraform-google-modules/network/google                    | 13.0.0   | VPC, subnets, secondary ranges               |
| cloud_router_nat   | terraform-google-modules/cloud-router/google               | 8.0.0    | Cloud Router + Cloud NAT                     |
| gke                | terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster | 41.0.2 | Private, VPC-native GKE Standard cluster     |

---

## Resources (high level)

Core resources managed by this configuration include:

- **Project APIs**
  - `google_project_service.host_compute`
  - `google_project_service.host_iam`
  - `google_project_service.host_cloudresourcemanager`
  - `google_project_service.service_compute`
  - `google_project_service.service_container`
  - `google_project_service.service_iam`
  - `google_project_service.service_cloudresourcemanager`

- **Networking / Shared VPC**
  - (optional, only when `enable_shared_vpc = true`):
    - `google_compute_shared_vpc_host_project`
    - `google_compute_shared_vpc_service_project`
  - `module.shared_vpc_network`:
    - VPC (`shared-vpc-network`)
    - Subnets:
      - `gke-subnet` (with `gke-pods` and `gke-services` secondary ranges)
      - `internal-subnet-1`
      - `internal-subnet-2`

- **NAT**
  - `module.cloud_router_nat`:
    - Cloud Router
    - Cloud NAT (`shared-vpc-nat`)

- **GKE**
  - `module.gke`:
    - Regional, VPC-native, **Standard** cluster
    - Private nodes (`enable_private_nodes = true`)
    - Public control plane endpoint (`enable_private_endpoint = false` by default)
    - Managed node pool (`primary-nodes`)

- **IAM**
  - `data.google_project.service`
  - `google_project_iam_member` bindings in the host project for:
    - GKE service agent (network user + host service agent user)
    - Cloud services SA (network user)

---

## Inputs

| Name                         | Description                                              | Type   | Default               | Required |
|------------------------------|----------------------------------------------------------|--------|-----------------------|----------|
| `enable_shared_vpc`          | Enable Shared VPC host/service binding (requires org)    | bool   | `false`               | no       |
| `host_project_id`            | GCP project ID of the Shared VPC **host** project        | string | n/a                   | yes      |
| `service_project_id`         | GCP project ID of the **service** project where GKE runs | string | n/a                   | yes      |
| `region`                     | GCP region for network and GKE cluster                   | string | `"us-central1"`       | no       |
| `network_name`               | Name of the Shared VPC network                           | string | `"shared-vpc-network"`| no       |
| `gke_subnet_name`            | Name of the subnet for GKE                               | string | `"gke-subnet"`        | no       |
| `gke_subnet_ip_cidr`         | CIDR of the GKE subnet                                   | string | `"10.0.0.0/20"`       | no       |
| `gke_subnet_private_ip_google_access` | Enable Private Google Access on the GKE subnet  | bool   | `true`                | no       |
| `internal_subnet_1_name`     | Name of the first internal subnet                        | string | `"internal-subnet-1"` | no       |
| `internal_subnet_1_ip_cidr`  | CIDR of the first internal subnet                        | string | `"10.3.0.0/20"`       | no       |
| `internal_subnet_1_private_ip_google_access` | Private Google Access on internal subnet 1 | bool | `true`              | no       |
| `internal_subnet_2_name`     | Name of the second internal subnet                       | string | `"internal-subnet-2"` | no       |
| `internal_subnet_2_ip_cidr`  | CIDR of the second internal subnet                       | string | `"10.4.0.0/20"`       | no       |
| `internal_subnet_2_private_ip_google_access` | Private Google Access on internal subnet 2 | bool | `true`              | no       |
| `gke_pods_secondary_range_name` | Name of the secondary range for Pods                 | string | `"gke-pods"`          | no       |
| `gke_pods_secondary_range_cidr` | CIDR of the secondary range for Pods                 | string | `"10.1.0.0/16"`       | no       |
| `gke_services_secondary_range_name` | Name of the secondary range for Services         | string | `"gke-services"`      | no       |
| `gke_services_secondary_range_cidr` | CIDR of the secondary range for Services         | string | `"10.2.0.0/20"`       | no       |
| `cloud_router_name`          | Name of the Cloud Router                                 | string | `"shared-vpc-nat-router"` | no   |
| `cloud_router_bgp_asn`       | BGP ASN for the Cloud Router                             | number | `65001`               | no       |
| `cloud_nat_name`             | Name of the Cloud NAT                                    | string | `"shared-vpc-nat"`    | no       |
| `cloud_nat_ip_allocate_option` | NAT IP allocation option (`AUTO_ONLY`, `MANUAL_ONLY`) | string | `"AUTO_ONLY"`         | no       |
| `cloud_nat_log_enable`       | Enable Cloud NAT logging                                 | bool   | `true`                | no       |
| `cloud_nat_log_filter`       | Cloud NAT logging filter                                 | string | `"ERRORS_ONLY"`       | no       |
| `gke_cluster_name`           | Name of the GKE cluster                                  | string | `"shared-vpc-gke"`    | no       |
| `gke_regional`               | Whether the cluster is regional (`true`) or zonal        | bool   | `true`                | no       |
| `gke_release_channel`        | GKE release channel (`RAPID`, `REGULAR`, `STABLE`)       | string | `"REGULAR"`           | no       |
| `gke_enable_private_nodes`   | Enable private nodes (no public IPs)                     | bool   | `true`                | no       |
| `gke_enable_private_endpoint`| Enable private control plane endpoint                    | bool   | `false`               | no       |
| `gke_master_ipv4_cidr_block` | CIDR block for master in private cluster                 | string | `"172.16.0.0/28"`     | no       |
| `gke_master_authorized_networks` | List of CIDR blocks allowed to reach control plane  | list(object) | see `variables.tf` default | no |
| `gke_node_pools`             | List of node pools configuration                         | list(object) | see `variables.tf` default | no |
| `gke_node_pools_oauth_scopes`| OAuth scopes per group for node pools                    | map(list(string)) | `{ all = ["https://www.googleapis.com/auth/cloud-platform"] }` | no |
| `gke_node_pools_labels`      | Labels per group for node pools                          | map(map(string)) | `{ all = { env = "prod" } }` | no |
| `gke_node_pools_tags`        | Network tags per group for node pools                    | map(list(string)) | `{ all = ["gke-node"] }` | no |

> Other configuration (remote state bucket, WIF provider, service account email, etc.) is managed outside of Terraform and referenced by the backend config and GitHub Actions workflow.

---

## Deployment modes: corporate vs sandbox

This module supports two main modes via `enable_shared_vpc`:

### 1. Corporate / Organization mode (Shared VPC)

Use when you have a **Google Cloud Organization** and want a proper **Shared VPC** topology.

```hcl
enable_shared_vpc = true

host_project_id    = "corp-shared-vpc-host"
service_project_id = "corp-gke-service"
region             = "us-central1"
```

Behavior:

- Creates:
  - `google_compute_shared_vpc_host_project` in `host_project_id`
  - `google_compute_shared_vpc_service_project` binding `service_project_id` to the host
- The VPC, subnets and NAT live in the **host** project.
- The GKE cluster runs in the **service** project, attached to the Shared VPC.

Requirements:

- Both projects must belong to the **same Organization**.
- The Terraform service account must have permissions to:
  - Enable required APIs
  - Manage Shared VPC and IAM bindings across host/service projects.

### 2. Sandbox / Personal mode (single project, no org)

Use when you are working with a **personal GCP account (`@gmail.com`)** or you **don’t have an Organization**.

```hcl
enable_shared_vpc = false

# Single-project topology: host == service
host_project_id    = "my-sandbox-project"
service_project_id = "my-sandbox-project"
region             = "us-central1"
```

Behavior:

- **Does not** create Shared VPC resources.
- The VPC, subnets, NAT and GKE cluster all live in the **same project**.
- Avoids the error:  
  *"Invalid resource usage: 'The project has no organization.'"*

This is ideal for labs, testing, and personal accounts, while keeping the same Terraform code compatible with corporate environments.

---

## Outputs

| Name           | Description                               |
|----------------|-------------------------------------------|
| `gke_name`     | Name of the GKE cluster                   |
| `gke_location` | Region of the GKE cluster                 |
| `gke_endpoint` | Public endpoint of the GKE control plane  |

---

## Architecture Overview

- **Shared VPC (optional)**:
  - When `enable_shared_vpc = true`:
    - Shared VPC configured in the **host project**.
    - Service project attached via `google_compute_shared_vpc_service_project`.
  - When `enable_shared_vpc = false`:
    - Single-project layout: `host_project_id == service_project_id`.
    - No Shared VPC host/service resources are created.

- **Network**:
  - 1 custom VPC: `shared-vpc-network`
  - Subnets:
    - `gke-subnet` (`10.0.0.0/20`) with:
      - Pods range: `gke-pods` (`10.1.0.0/16`)
      - Services range: `gke-services` (`10.2.0.0/20`)
    - `internal-subnet-1` (`10.3.0.0/20`)
    - `internal-subnet-2` (`10.4.0.0/20`)
  - Cloud Router + Cloud NAT providing egress for private workloads.

- **GKE cluster**:
  - Regional, VPC-native cluster
  - Private nodes (no public IPs on nodes)
  - Public API server endpoint, restricted via `master_authorized_networks`
  - Managed node pool with configurable machine type and size (default `e2-medium` in prod examples)

- **Project APIs**:
  - Terraform enables required APIs in both host and service projects:
    - `compute.googleapis.com`
    - `container.googleapis.com`
    - `iam.googleapis.com`
    - `cloudresourcemanager.googleapis.com`
  - APIs are created with `disable_on_destroy = false` so a Terraform destroy will not disable them.

- **IAM**:
  - GKE service agent and Cloud Services SA of the service project are granted:
    - `roles/compute.networkUser` in the host project
    - `roles/container.hostServiceAgentUser` in the host project (for the GKE service agent)
  - Terraform service account has the roles required to create/update these resources.

---

## Remote State (GCS)

State is stored in a **GCS bucket** (created outside Terraform), configured in `backend.tf`:

```hcl
terraform {
  backend "gcs" {
    bucket = "tfstate-org-shared"
    prefix = "envs/prod/shared-vpc-gke"
    # encryption_key = "projects/infra-shared/locations/us-central1/keyRings/tfstate-keyring/cryptoKeys/tfstate-key"
  }
}
```

Recommended settings for the state bucket:

- **Uniform bucket-level access**
- **Versioning enabled**
- Optional: **CMEK** encryption via Cloud KMS
- IAM:
  - Terraform SA: `roles/storage.objectAdmin` (or custom minimal role)
  - No `allUsers` / `allAuthenticatedUsers` access

---

## CI/CD – GitHub Actions (Terraform Plan)

A GitHub Actions workflow (`.github/workflows/terraform-plan-prod.yml`) runs `terraform plan` on PRs targeting `main` and touching `terraform/env/test/**`.

Key points:

- Uses **Workload Identity Federation** (no static JSON keys):
  - Action: `google-github-actions/auth@v2`
  - Requires:
    - `vars.GCP_WIF_PROVIDER` → full resource name of the Workload Identity Provider
    - `vars.GCP_TF_SERVICE_ACCOUNT` → Terraform service account email
- Steps:
  - Checkout repo
  - Authenticate to GCP via WIF
  - Install Terraform (`hashicorp/setup-terraform@v2`)
  - Render `terraform.tfvars` from environment variables (in CI)
  - `terraform fmt -check`
  - `terraform init`
  - `terraform validate`
  - `terraform plan` (output saved to `plan.out`)
  - Comment the plan in the PR using `actions/github-script@v8`

Example auth step:

```yaml
- name: Authenticate to Google Cloud (WIF)
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
    service_account: ${{ vars.GCP_TF_SERVICE_ACCOUNT }}
    create_credentials_file: true
    export_environment_variables: true
```

---

## Prerequisites

- **GCP**:
  - Organization + billing configured **(only required for `enable_shared_vpc = true`)**
  - Host and service projects created
  - Permissions for the Terraform service account to:
    - Enable required APIs in both projects (`google_project_service`)
    - Manage networking, GKE, and IAM as defined in this module

- **Terraform service account**:
  - Appropriate IAM roles in host + service projects and state bucket project
  - `roles/cloudkms.cryptoKeyEncrypterDecrypter` if using CMEK for the state bucket

- **Workload Identity Federation**:
  - Workload Identity Pool + OIDC Provider for the GitHub repo
  - Binding `roles/iam.workloadIdentityUser` on the Terraform SA to the pool/provider principal set

- **GitHub**:
  - Repository or environment variables:
    - `GCP_WIF_PROVIDER`
    - `GCP_TF_SERVICE_ACCOUNT`
    - Project IDs / regions to render `terraform.tfvars` in CI

---
