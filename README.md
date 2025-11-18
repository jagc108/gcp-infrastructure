# GCP Shared VPC + GKE (Prod)

Terraform configuration to provision:

- A **Shared VPC** in a **host project**
- **3 subnets** (one for GKE with secondary ranges, two internal)
- **Cloud Router + Cloud NAT**
- A **private, VPC-native GKE Standard cluster** in a **service project** using the Shared VPC
- **IAM bindings** required for GKE + Shared VPC
- **Remote state** stored in a GCS bucket
- **GitHub Actions** workflows for `terraform plan & apply` using **Workload Identity Federation (WIF)**

This repo is structured around `terraform/`.

---

## Usage

From the repo root:

```bash
cd terraform

# Set required variables (example)
export TF_VAR_host_project_id="my-host-project"
export TF_VAR_service_project_id="my-service-project"
export TF_VAR_region="us-central1"

terraform init
terraform plan
terraform apply
```

Remote state is configured with a GCS backend in `backend.tf`.  
Make sure the bucket exists and the Terraform service account has access.

---

## Requirements

| Name      | Version   |
|-----------|-----------|
| terraform | >= 1.5.0  |
| google    | ~> 5.0    |

---

## Providers

| Name    | Version | Description                       |
|---------|---------|-----------------------------------|
| google  | ~> 5.0  | Default provider (host project)   |
| google.service | ~> 5.0 | Aliased provider (service project) |

---

## Modules

| Name                | Source                                                     | Version  | Description                            |
|---------------------|------------------------------------------------------------|----------|----------------------------------------|
| shared_vpc_network  | terraform-google-modules/network/google                    | 13.0.0   | VPC, subnets, secondary ranges         |
| cloud_router_nat    | terraform-google-modules/cloud-router/google               | 8.0.0    | Cloud Router + Cloud NAT               |
| gke                 | terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster | 41.0.2 | Private, VPC-native GKE Standard cluster |

---

## Resources (high level)

Core resources managed by this configuration include:

- **Networking / Shared VPC**
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
    - Public control plane endpoint (`enable_private_endpoint = false`)
    - Managed node pool (`primary-nodes`)
- **IAM**
  - `data.google_project.service`
  - `google_project_iam_member` bindings in the host project for:
    - GKE service agent (network user + host service agent user)
    - Cloud services SA (network user)

---

## Inputs

| Name               | Description                                         | Type   | Default       | Required |
|--------------------|-----------------------------------------------------|--------|---------------|----------|
| `host_project_id`  | GCP project ID of the Shared VPC **host** project   | string | n/a           | yes      |
| `service_project_id` | GCP project ID of the **service** project where GKE runs | string | n/a      | yes      |
| `region`           | GCP region for network and GKE cluster              | string | `"us-central1"` | no    |

> Other configuration (remote state bucket, WIF provider, service account email, etc.) is managed outside of Terraform and referenced by the backend config and GitHub Actions workflow.

---

## Outputs

| Name           | Description                               |
|----------------|-------------------------------------------|
| `gke_name`     | Name of the GKE cluster                   |
| `gke_location` | Region of the GKE cluster                 |
| `gke_endpoint` | Public endpoint of the GKE control plane  |

---

## Architecture Overview

- **Shared VPC** lives in the **host project**:
  - 1 custom VPC: `shared-vpc-network`
  - Subnets:
    - `gke-subnet` (`10.0.0.0/20`) with:
      - Pods range: `gke-pods` (`10.1.0.0/16`)
      - Services range: `gke-services` (`10.2.0.0/20`)
    - `internal-subnet-1` (`10.3.0.0/20`)
    - `internal-subnet-2` (`10.4.0.0/20`)
  - Cloud Router + Cloud NAT providing egress for private workloads.

- **GKE cluster** runs in the **service project**, attached to the Shared VPC:
  - Regional, VPC-native cluster
  - Private nodes (no public IPs on nodes)
  - Public API server endpoint, restricted via `master_authorized_networks`
  - Managed node pool with `e2-medium` nodes

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

A GitHub Actions workflow (`.github/workflows/terraform-plan-prod.yml`) runs `terraform plan` on PRs targeting `main` and touching `environments/prod/**`.

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
  - Organization + billing configured
  - Host and service projects created
  - APIs enabled:
    - `compute.googleapis.com`
    - `container.googleapis.com`
    - `iam.googleapis.com`
    - `cloudresourcemanager.googleapis.com`
- **Terraform service account**:
  - Appropriate IAM roles in host + service projects and state bucket project
- **Workload Identity Federation**:
  - Workload Identity Pool + OIDC Provider for the GitHub repo
  - Binding `roles/iam.workloadIdentityUser` on the Terraform SA to the pool/provider principal set
- **GitHub**:
  - Repository variables:
    - `GCP_WIF_PROVIDER`
    - `GCP_TF_SERVICE_ACCOUNT`

---
