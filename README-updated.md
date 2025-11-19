# GCP Shared VPC + GKE (Prod/Test)

Terraform configuration to provision:

- A **Shared VPC** in a **host project** (optional, for corporate orgs)
- **3 subnets** (one for GKE with secondary ranges, two internal)
- **Cloud Router + Cloud NAT**
- A **private, VPC-native GKE Standard cluster** in a **service project** (or same project in sandbox)
- **IAM bindings** required for GKE + Shared VPC (when enabled)
- **Required GCP APIs enabled** in host and service projects
- **Remote state** stored in a GCS bucket
- **GitHub Actions** workflows for:
  - `terraform plan` (prod)
  - `terraform apply` (test)
  - `terraform destroy -plan` (test)
  - `terraform destroy` (test)
  using **Workload Identity Federation (WIF)**

Repo layout (simplified):

- `environments/prod/` → prod infra (Shared VPC + GKE)
- `terraform/env/test/` → test environment (same stack adapted to test)
- `.github/workflows/` → CI/CD workflows (plan/apply/destroy)
- `README-ci-wif.md` → detailed guide for SA + WIF + GitHub Actions auth

---

## Usage (prod example)

From the repo root:

```bash
cd environments/prod

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

## Inputs (high level)

Key inputs from `variables.tf` (simplified):

- **Mode / topology**
  - `enable_shared_vpc` (bool, default `false`):  
    - `true` → corporate mode (Shared VPC host + service projects, requires Organization)
    - `false` → sandbox mode (single project: host == service)

- **Projects / region**
  - `host_project_id` (string): project where the VPC/NAT live
  - `service_project_id` (string): project where the GKE cluster lives
  - `region` (string, default `us-central1`)

- **Network**
  - `network_name` (default `shared-vpc-network`)
  - Subnets + secondary ranges:
    - `gke_subnet_name`, `gke_subnet_ip_cidr`, `gke_subnet_private_ip_google_access`
    - `internal_subnet_1_*`, `internal_subnet_2_*`
    - `gke_pods_secondary_range_*`, `gke_services_secondary_range_*`

- **Cloud Router / NAT**
  - `cloud_router_name`, `cloud_router_bgp_asn`
  - `cloud_nat_name`, `cloud_nat_ip_allocate_option`, `cloud_nat_log_enable`, `cloud_nat_log_filter`

- **GKE cluster**
  - `gke_cluster_name`, `gke_regional`, `gke_release_channel`
  - `gke_enable_private_nodes`, `gke_enable_private_endpoint`
  - `gke_master_ipv4_cidr_block`
  - `gke_master_authorized_networks`
  - `gke_node_pools` (name, machine_type, min/max, autoscaling, etc.)
  - `gke_node_pools_oauth_scopes`
  - `gke_node_pools_labels`
  - `gke_node_pools_tags`
  - `gke_deletion_protection` (bool, default `true`)

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
  _"Invalid resource usage: 'The project has no organization.'"_

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
  - Managed node pool with configurable machine type and size (default `e2-medium` in examples)
  - Optional deletion protection via `gke_deletion_protection`:
    - `true` in prod (you must first set to `false` then apply, then destroy)
    - `false` in sandbox to allow direct `terraform destroy`

- **Project APIs**:
  - Terraform enables required APIs in both host and service projects:
    - `compute.googleapis.com`
    - `container.googleapis.com`
    - `iam.googleapis.com`
    - `cloudresourcemanager.googleapis.com`
  - APIs are created with `disable_on_destroy = false` so a Terraform destroy will not disable them.

- **IAM**:
  - When using Shared VPC, IAM bindings are created so:
    - GKE service agent and Cloud Services SA of the service project can use the host VPC.
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
  - Terraform SA: `roles/storage.objectAdmin` (or a more restricted custom role)
  - No `allUsers` / `allAuthenticatedUsers` access

---

## CI/CD – GitHub Actions (Terraform + WIF)

This repository includes several GitHub Actions workflows that use:

- **Workload Identity Federation** (WIF) to authenticate to GCP (without JSON keys)
- The same Terraform code, but targeting different directories / environments

The detailed, step-by-step setup of the **Terraform Service Account** and **Workload Identity Federation** is documented in:

👉 **[README-ci-wif.md](README-ci-wif.md)**

### 1. Terraform Plan – Prod

**File (example):**

- `.github/workflows/terraform-plan-prod.yml` (not shown here, but described previously)

**Purpose:**

- Run `terraform plan` for the **prod** environment (`environments/prod/`) on every Pull Request to `main` that touches `environments/prod/**`.
- Post the Terraform plan as a **comment on the PR**.

**Key points:**

- Uses **WIF** via `google-github-actions/auth@v2`.
- Uses repo/environment variables:
  - `GCP_WIF_PROVIDER`
  - `GCP_TF_SERVICE_ACCOUNT`
- Renders a `terraform.tfvars` file on the fly using GitHub env/vars.
- Runs:
  - `terraform fmt -check`
  - `terraform init`
  - `terraform validate`
  - `terraform plan`
- Uploads the plan into a PR comment.

See `README-ci-wif.md` for the full YAML and explanation of SA + WIF.

---

### 2. Terraform Apply – Test

**File:**

- `.github/workflows/tf_apply.yaml`

```yaml
name: Terraform apply - Test

on:
  workflow_dispatch:
  push:
    branches:
      - main
    paths:
      - "terraform/env/test/**"

env:
  TF_INPUT: false

permissions:
  id-token: write        # necesario para OIDC/WIF con GCP
  contents: read
  pull-requests: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ./terraform/env/test

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # === Autenticación contra GCP usando Workload Identity Federation ===
      - name: Authenticate to Google Cloud (WIF)
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_TF_SERVICE_ACCOUNT }}
          create_credentials_file: true
          export_environment_variables: true

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.13.5

      - name: Terraform Init
        id: init
        run: terraform init

      - name: Terraform Apply
        id: apply
        run: |
          terraform apply             -var "host_project_id=${{ vars.HOST_PROJECT_ID }}"             -var "service_project_id=${{ vars.SERVICE_PROJECT_ID }}"             -var "region=${{ vars.REGION }}"             -auto-approve
```

**What it does:**

- **Environment:** `terraform/env/test` (test environment).
- **Triggers:**
  - `workflow_dispatch` → manual run from the GitHub UI.
  - `push` to `main` that touches `terraform/env/test/**`.
- **Auth:** uses WIF (same pattern as in prod plan).
- **Terraform:**
  - `terraform init`
  - `terraform apply` with:
    - `host_project_id`, `service_project_id`, `region` passed from repo/env vars.
  - `-auto-approve` → applies without interactive confirmation (only use this in non-prod or with proper review gates).

Use this workflow to **deploy/apply changes automatically** to the **test environment**.

---

### 3. Terraform Destroy – Plan (Test)

**File:**

- `.github/workflows/tf_destroy_plan.yaml`

```yaml
name: Terraform Destroy Plan - Test

on:
  workflow_dispatch:

env:
  TF_INPUT: false

permissions:
  id-token: write        # necesario para OIDC/WIF con GCP
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ./terraform/env/test

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud (WIF)
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_TF_SERVICE_ACCOUNT }}
          create_credentials_file: true
          export_environment_variables: true

      - name: Terraform - Setup
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.13.5

      - name: Terraform - Format and style
        id: fmt
        run: terraform fmt -check -diff -recursive
        continue-on-error: true

      - name: Terraform - Init
        id: init
        run: terraform init

      - name: Terraform - Validate
        id: validate
        run: terraform validate -no-color

      - name: Terraform Destroy - Plan
        id: plan
        run: |
          terraform plan             -var "host_project_id=${{ vars.HOST_PROJECT_ID }}"             -var "service_project_id=${{ vars.SERVICE_PROJECT_ID }}"             -var "region=${{ vars.REGION }}"             -no-color -destroy
```

**What it does:**

- **Environment:** `terraform/env/test`.
- **Trigger:** only `workflow_dispatch` (manual).
- **Auth:** WIF.
- **Terraform:**
  - `fmt` (check only)
  - `init`
  - `validate`
  - `plan -destroy` → shows what would be deleted in the test stack, **without** actually destroying resources.

Use this workflow when you want to **review the destruction plan** of the test environment before running the real `destroy`.

---

### 4. Terraform Destroy – Run (Test)

**File:**

- `.github/workflows/tf_destroy_run.yaml`

```yaml
name: Terraform Destroy - Test

on:
  workflow_dispatch:

env:
  TF_INPUT: false

permissions:
  id-token: write        # necesario para OIDC/WIF con GCP
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ./terraform/env/test

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud (WIF)
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_TF_SERVICE_ACCOUNT }}
          create_credentials_file: true
          export_environment_variables: true

      - name: Terraform - Setup
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.13.5

      - name: Terraform - Format and style
        id: fmt
        run: terraform fmt -check -diff -recursive
        continue-on-error: true

      - name: Terraform - Init
        id: init
        run: terraform init

      - name: Terraform - Validate
        id: validate
        run: terraform validate -no-color

      - name: Terraform - Destroy
        id: plan
        run: |
          terraform destroy             -var "host_project_id=${{ vars.HOST_PROJECT_ID }}"             -var "service_project_id=${{ vars.SERVICE_PROJECT_ID }}"             -var "region=${{ vars.REGION }}"             -auto-approve
```

**What it does:**

- **Environment:** `terraform/env/test`.
- **Trigger:** `workflow_dispatch` (manual only).
- **Auth:** WIF.
- **Terraform:**
  - `fmt` (check only)
  - `init`
  - `validate`
  - `destroy -auto-approve` → actually **destroys** all Terraform-managed resources in the test environment.

> ⚠️ Use this workflow with care.  
> In test/sandbox this is fine, but in prod you’d typically:
> - Require extra approvals, or
> - Use a multi-step process (`plan -destroy` + manual apply), or
> - Keep `deletion_protection = true` on critical resources (e.g., GKE clusters) and explicitly disable it before destroy.

---

## More details: SA + WIF setup

For a detailed, step-by-step guide on how to:

- Create the **Terraform Service Account**  
- Configure **Workload Identity Federation** (Workload Identity Pool + Provider)  
- Bind the pool to the SA (`roles/iam.workloadIdentityUser`)  
- Wire variables (`GCP_WIF_PROVIDER`, `GCP_TF_SERVICE_ACCOUNT`, etc.) in GitHub

👉 See **[README-ci-wif.md](README-ci-wif.md)**.

