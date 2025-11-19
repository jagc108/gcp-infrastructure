# Terraform CI with GitHub Actions and Workload Identity Federation

This document explains **step by step** how to:

1. Create a **Terraform Service Account (TF SA)** in GCP  
2. Configure **Workload Identity Federation (WIF)** so **GitHub Actions** can impersonate that SA  
3. Understand **how IAM permissions differ** between:
   - **Sandbox / single-project deployments**
   - **Corporate / Shared VPC deployments**
4. Wire everything into the **Terraform workflows** in this repo.

It is a companion to the main `README.md` and the GitHub Actions workflows under `.github/workflows/`.

Repo reference:

- GitHub repo: `jagc108/gcp-infrastructure` (adjust if you fork/rename)
- Terraform environments:
  - `terraform/env/test/` (test/sandbox)

---

## 0. Concepts (very short version)

- **Terraform Service Account (TF SA)**  
  The identity in GCP that actually creates/updates/destroys resources when Terraform runs from GitHub Actions.

- **Workload Identity Pool & Provider (WIF)**  
  A GCP mechanism that allows **external identities** (GitHub Actions OIDC tokens) to obtain **short-lived credentials** for a GCP service account **without JSON keys**.

- **GitHub Actions OIDC**  
  Each GitHub workflow run can request an **OIDC token** signed by GitHub.  
  GCP verifies that token and, if it matches your conditions (repo, branch, etc.), allows impersonation of the TF SA.

- **Deployment modes in this repo**  
  - **Sandbox / Personal**: no org, single project; `host_project_id == service_project_id`.  
  - **Corporate / Org**: Shared VPC host project + GKE service project; requires Organization.

Most of the WIF setup is identical in both modes; what changes mainly is **where you grant IAM roles**.

---

## 1. Choose your deployment mode

Before creating roles and WIF, decide which mode you’re using.

### 1.1. Sandbox / Single-project mode

Use this if:

- You have a **personal account** (`@gmail.com`) or
- You don’t have a **Google Cloud Organization**, or
- You just want a **lab/sandbox** without Shared VPC.

Terraform variables:

```hcl
enable_shared_vpc  = false
host_project_id    = "my-sandbox-project"
service_project_id = "my-sandbox-project"
region             = "us-central1"
```

In this mode:

- All resources (VPC, NAT, GKE, IAM, APIs) live in the **same project**.
- You ONLY grant strong IAM roles to the TF SA in **that one project**.

### 1.2. Corporate / Shared VPC mode

Use this if:

- You have a **Google Cloud Organization**, and
- You want a **Shared VPC** topology (separate host + service projects).

Terraform variables:

```hcl
enable_shared_vpc  = true
host_project_id    = "corp-shared-vpc-host"
service_project_id = "corp-gke-service"
region             = "us-central1"
```

In this mode:

- **Host project**: owns the VPC, subnets, Cloud Router, NAT.
- **Service project**: owns the GKE cluster.
- Terraform must have IAM in **both** host and service projects.
- Additional IAM bindings let the **GKE service agent** of the service project use the Shared VPC in the host project.

---

## 2. Common setup: variables and Terraform Service Account

These steps are the same for sandbox and corporate, only the project IDs differ.

### 2.1. Define variables

Choose your project IDs and names:

```bash
# Project where the TF SA and WIF will live
# Sandbox: this is usually also your host/service project
INFRA_PROJECT_ID="aerobic-pivot-632458-k7"

# Sandbox mode (single project):
SANDBOX_PROJECT_ID="aerobic-pivot-632458-k7"

# Corporate mode: separate host/service projects
HOST_PROJECT_ID="corp-shared-vpc-host"
SERVICE_PROJECT_ID="corp-gke-service"

# Terraform service account
TF_SA_NAME="github-tf-prod"
TF_SA_DISPLAY_NAME="Terraform SA for GitHub Actions"

# GitHub repo (org/repo)
GITHUB_REPO="jagc108/gcp-infrastructure"

# WIF pool/provider IDs
WIP_POOL_ID="github-pool"
WIP_POOL_DISPLAY_NAME="GitHub Actions Pool"
WIP_PROVIDER_ID="github-actions"
WIP_PROVIDER_DISPLAY_NAME="GitHub Actions provider for this repo"
```

### 2.2. Create the Terraform Service Account (TF SA)

Create the SA in the **infra project**:

```bash
gcloud config set project "${INFRA_PROJECT_ID}"

gcloud iam service-accounts create "${TF_SA_NAME}"   --project="${INFRA_PROJECT_ID}"   --display-name="${TF_SA_DISPLAY_NAME}"

TF_SA_EMAIL="${TF_SA_NAME}@${INFRA_PROJECT_ID}.iam.gserviceaccount.com"
echo "${TF_SA_EMAIL}"
```

You will:

- Grant IAM roles to this SA in the relevant projects.
- Allow the Workload Identity Pool to impersonate this SA.
- Use its email (`TF_SA_EMAIL`) in GitHub Actions (`GCP_TF_SERVICE_ACCOUNT`).

---

## 3. IAM for Terraform SA – Sandbox mode

In **sandbox mode**, you have a single project where everything lives:

```bash
PROJECT_ID="${SANDBOX_PROJECT_ID}" 
```

Terraform controls:

- Network (VPC, subnets, NAT, router)
- GKE cluster + node pools
- IAM bindings on GKE SAs
- Enabling required APIs

Because all of that happens in **one project**, you only need to grant roles in that project.

### 3.1. IAM roles for TF SA (sandbox)

```bash
# GKE admin (includes container.clusters.list, manage clusters, etc.)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/container.admin"

# Network + compute operations (VPC, subnets, routers, etc.)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/compute.networkAdmin"

# Create and manage service accounts (for cluster/node SAs)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/iam.serviceAccountAdmin"

# ➕ IMPORTANT: allow the TF SA to "act as" other service accounts (like the GKE SA it creates)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/iam.serviceAccountUser"

# Enable/disable services from Terraform (google_project_service)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/serviceusage.serviceUsageAdmin"

# Manage IAM bindings at project level
# (needed for the module to give roles to GKE SAs, e.g. monitoring.metricWriter)
gcloud projects add-iam-policy-binding "${PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/resourcemanager.projectIamAdmin"
```

Why `roles/iam.serviceAccountUser` matters:

- The GKE module creates a service account like `tf-gke-<cluster>-<suffix>@PROJECT_ID.iam.gserviceaccount.com`.
- When creating the cluster, GKE needs to **use** that SA.
- The caller (your TF SA) must have `iam.serviceAccounts.actAs` on that SA.
- That permission is provided by `roles/iam.serviceAccountUser` on the project.

Without it, you see errors like:

```text
The user does not have access to service account "...". Ask a project owner to grant you the iam.serviceAccountUser role on the service account.
```

### 3.2. Enable APIs in sandbox project

```bash
gcloud services enable   container.googleapis.com   compute.googleapis.com   iam.googleapis.com   cloudresourcemanager.googleapis.com   --project="${PROJECT_ID}"
```

In sandbox, there is no Shared VPC, so you don’t need cross-project IAM or host/service separation.

---

## 4. IAM for Terraform SA – Corporate / Shared VPC mode

In **corporate mode**, there are at least two projects:

- `HOST_PROJECT_ID` → Shared VPC host (VPC, subnets, NAT, router)
- `SERVICE_PROJECT_ID` → GKE cluster running in a different project

Terraform must:

- Create and manage network/NAT in the **host project**.
- Attach the **service project** to the Shared VPC.
- Create and manage GKE cluster in the **service project**.
- Grant IAM to GKE service agents in the **host** project so GKE can use the Shared VPC.

### 4.1. IAM roles for TF SA on HOST project

```bash
# Host project: networking + IAM + APIs + let GKE use the network
gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/serviceusage.serviceUsageAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/resourcemanager.projectIamAdmin"

# Optional/depending on org policies: allow managing IAM for networking
gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/iam.securityAdmin"

# Some GKE operations on Shared VPC rely on container roles in host
gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/container.admin"
```

> Nota: en el host project, el TF SA normalmente **no necesita** `iam.serviceAccountUser`,  
> porque las SAs que va a “actuar como” (GKE node SAs) viven en el service project.

### 4.2. IAM roles for TF SA on SERVICE project

```bash
# Service project: GKE clusters, node SAs, IAM, APIs
gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/container.admin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/iam.serviceAccountAdmin"

# ➕ IMPORTANT: allow the TF SA to "act as" the GKE service accounts it creates in the service project
gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/serviceusage.serviceUsageAdmin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}"   --member="serviceAccount:${TF_SA_EMAIL}"   --role="roles/resourcemanager.projectIamAdmin"
```

Again, `roles/iam.serviceAccountUser` is what prevents:

```text
The user does not have access to service account "tf-gke-...". Ask a project owner to grant you the iam.serviceAccountUser role...
```

### 4.3. Enable APIs in host and service projects

```bash
gcloud services enable   container.googleapis.com   compute.googleapis.com   iam.googleapis.com   cloudresourcemanager.googleapis.com   --project="${HOST_PROJECT_ID}"

gcloud services enable   container.googleapis.com   compute.googleapis.com   iam.googleapis.com   cloudresourcemanager.googleapis.com   --project="${SERVICE_PROJECT_ID}"
```

Con esto, Terraform puede aprovisionar:

- La Shared VPC en el host project.
- El GKE cluster en el service project.
- Los IAM necesarios para que el **GKE service agent** del service project use la red del host.
- Las SAs de GKE y los bindings que el módulo necesita.

---

## 5. WIF – Common for both sandbox and corporate

The WIF setup is **identical** regardless of deployment mode.  
The only difference is which `INFRA_PROJECT_ID` you choose (often the same as sandbox project, or a dedicated “infra” project in corporate).

### 5.1. Enable APIs for WIF in infra project

```bash
gcloud config set project "${INFRA_PROJECT_ID}"

gcloud services enable   iam.googleapis.com   iamcredentials.googleapis.com   sts.googleapis.com   cloudresourcemanager.googleapis.com
```

### 5.2. Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "${WIP_POOL_ID}"   --project="${INFRA_PROJECT_ID}"   --location="global"   --display-name="${WIP_POOL_DISPLAY_NAME}"
```

Get its full name:

```bash
WIP_POOL_FULL_NAME=$(gcloud iam workload-identity-pools describe "${WIP_POOL_ID}"   --project="${INFRA_PROJECT_ID}"   --location="global"   --format="value(name)")

echo "${WIP_POOL_FULL_NAME}"
# e.g. projects/123456789012/locations/global/workloadIdentityPools/github-pool
```

### 5.3. Create Workload Identity Provider (GitHub OIDC)

```bash
gcloud iam workload-identity-pools providers create-oidc "${WIP_PROVIDER_ID}"   --project="${INFRA_PROJECT_ID}"   --location="global"   --workload-identity-pool="${WIP_POOL_ID}"   --display-name="${WIP_PROVIDER_DISPLAY_NAME}"   --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref"   --attribute-condition="assertion.repository == \"${GITHUB_REPO}\""   --issuer-uri="https://token.actions.githubusercontent.com"
```

Get the provider name (for GitHub Actions):

```bash
gcloud iam workload-identity-pools providers describe "${WIP_PROVIDER_ID}"   --project="${INFRA_PROJECT_ID}"   --location="global"   --workload-identity-pool="${WIP_POOL_ID}"   --format="value(name)"
# e.g. projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-actions
```

### 5.4. Allow pool identities to impersonate the TF SA

```bash
gcloud iam service-accounts add-iam-policy-binding "${TF_SA_EMAIL}"   --project="${INFRA_PROJECT_ID}"   --role="roles/iam.workloadIdentityUser"   --member="principalSet://iam.googleapis.com/${WIP_POOL_FULL_NAME}/attribute.repository/${GITHUB_REPO}"
```

Now any GitHub Actions job from that repo (matching the provider condition) can impersonate the TF SA.

---

## 6. GitHub Actions configuration

You need two key values from the previous steps:

- **Terraform SA email** (from step 2.2):

  ```text
  github-tf-prod@INFRA_PROJECT_ID.iam.gserviceaccount.com
  ```

- **Workload Identity Provider resource name** (from step 5.3), e.g.:

  ```text
  projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-actions
  ```

In GitHub (Settings → Environments → `prod` / `test`), define:

- `GCP_TF_SERVICE_ACCOUNT` → TF SA email  
- `GCP_WIF_PROVIDER` → full WIF provider name  
- `HOST_PROJECT_ID` / `SERVICE_PROJECT_ID` / `REGION` (for test workflows)  
- `HOST_PROJECT_ID_PROD` / `SERVICE_PROJECT_ID_PROD` / `REGION_PROD` (for prod plan workflow)

---

## 7. Terraform workflows overview

This repo includes several workflows that rely on the SA + WIF config described above:

### 7.1. Terraform Plan – Prod

- Path: `environments/prod/`
- Trigger: `pull_request` to `main` touching `environments/prod/**`.
- Auth: `google-github-actions/auth@v2` with WIF.
- Steps:
  - `terraform fmt -check`
  - `terraform init`
  - `terraform validate`
  - `terraform plan`
  - Post plan output as a PR comment.

### 7.2. Terraform Apply – Test

- Path: `terraform/env/test/`
- Trigger: `workflow_dispatch` + `push` to `main` touching `terraform/env/test/**`.
- Auth: WIF.
- Runs `terraform apply -auto-approve` using vars from environment (`HOST_PROJECT_ID`, `SERVICE_PROJECT_ID`, `REGION`).

### 7.3. Terraform Destroy – Plan (Test)

- Path: `terraform/env/test/`
- Trigger: `workflow_dispatch`.
- Auth: WIF.
- Runs `terraform plan -destroy` (no actual deletion), to review the destruction.

### 7.4. Terraform Destroy – Run (Test)

- Path: `terraform/env/test/`
- Trigger: `workflow_dispatch`.
- Auth: WIF.
- Runs `terraform destroy -auto-approve` to fully tear down the test stack.

> ⚠️ For **prod**, usually you:
> - Keep `gke_deletion_protection = true` by default.
> - Use `plan` only in CI, and run `apply`/`destroy` manually or with extra approvals.

---

## 8. Recap: what changes between sandbox and corporate?

- **Sandbox / single-project**
  - Terraform uses a **single project** for everything (host + service).
  - All IAM roles for the TF SA are granted in **that one project**  
    (including `roles/iam.serviceAccountUser`).
  - No Shared VPC resources or cross-project IAM needed.
  - Simpler, ideal for personal labs.

- **Corporate / Shared VPC**
  - Terraform uses **two projects**: host (network) + service (GKE).
  - TF SA gets roles in **both** host and service projects.
  - `roles/iam.serviceAccountUser` is required **at least in the service project**  
    so the TF SA can “act as” the GKE SAs it creates.
  - Shared VPC host/service bindings and IAM for GKE service agents are created.
  - Requires a **Google Cloud Organization** and org-level governance.

Once your SA + WIF + IAM configuration matches your chosen mode, the Terraform workflows in this repo should run without 403 “permission denied” errors and you can focus on the infrastructure itself.
