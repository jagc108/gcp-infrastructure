# GitHub Actions + Workload Identity Federation for Terraform

This document explains **step by step** how to:

1. Create a **Terraform Service Account (SA)** in GCP  
2. Configure **Workload Identity Federation (WIF)** so **GitHub Actions** can impersonate that SA  
3. Wire everything into the **Terraform plan** workflow for this repo

It is written for the repo:

- `jagc108/gcp-infrastructure` (adjust if you fork/rename)

And assumes the Terraform code is under:

- `terraform/env/test`

---

## 0. Concepts (very short version)

- **Terraform Service Account (TF SA)**:  
  The identity in GCP that actually creates/updates/destroys resources.

- **Workload Identity Pool & Provider (WIP)**:  
  A GCP mechanism that allows **external identities** (GitHub Actions OIDC tokens in this case) to obtain **short‑lived credentials** for a GCP service account **without** using long‑lived JSON keys.

- **GitHub Actions OIDC**:  
  GitHub emits an **OIDC token** for each workflow run. GCP verifies that token and, if it matches your conditions (repo, branch, etc.), allows impersonation of the TF SA.

---

## 1. Naming and variables

Pick the following values (adapt names to your org):

```bash
# Project where the TF SA and WIF pool/provider will live
INFRA_PROJECT_ID="my-host-project-id"   # or a dedicated infra project

# Host and service projects (can be the same as INFRA in sandbox)
HOST_PROJECT_ID="my-host-project-id"
SERVICE_PROJECT_ID="my-service-project-id"

# Terraform service account
TF_SA_NAME="github-tf-prod"
TF_SA_DISPLAY_NAME="Terraform SA for GitHub Actions - prod"

# Workload Identity Pool + Provider
WIP_POOL_ID="github-pool"
WIP_POOL_DISPLAY_NAME="GitHub Actions Pool"

WIP_PROVIDER_ID="github-actions-prod"
WIP_PROVIDER_DISPLAY_NAME="GitHub Actions provider for gcp-infrastructure prod"

# GitHub repo (org/repo)
GITHUB_REPO="jagc108/gcp-infrastructure"
```

---

## 2. Enable required APIs

In the **INFRA project** (where you create WIF and the TF SA), enable:

```bash
gcloud config set project "${INFRA_PROJECT_ID}"

gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com
```

If your **host** and **service** projects differ from `INFRA_PROJECT_ID`, they also need:

```bash
gcloud services enable compute.googleapis.com container.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com
```

---

## 3. Create the Terraform Service Account

Create the SA in the **INFRA project**:

```bash
gcloud iam service-accounts create "${TF_SA_NAME}" --project="${INFRA_PROJECT_ID}" --display-name="${TF_SA_DISPLAY_NAME}"
```

Get its email:

```bash
TF_SA_EMAIL="${TF_SA_NAME}@${INFRA_PROJECT_ID}.iam.gserviceaccount.com"
echo "${TF_SA_EMAIL}"
```

You’ll use this email in:

- IAM bindings (projects + state bucket)
- Workload Identity binding
- GitHub Actions `GCP_TF_SERVICE_ACCOUNT` variable

---

## 4. Grant IAM roles to the Terraform SA

### 4.1. On the host project (network, NAT, IAM, APIs)

The TF SA needs enough permissions to:

- Manage VPC, subnets, Cloud Router, NAT
- Configure Shared VPC (in corporate mode)
- Manage IAM bindings in the host project
- Enable required APIs via `google_project_service`

Example (min-viable, still a bit coarse; in real org you might create a custom role):

```bash
# Host project: networking + IAM + APIs
gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/iam.securityAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/serviceusage.serviceUsageAdmin"

gcloud projects add-iam-policy-binding "${HOST_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/container.admin"
```

### 4.2. On the service project (GKE, IAM, APIs)

```bash
# Service project: GKE + IAM + APIs
gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/container.admin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding "${SERVICE_PROJECT_ID}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/serviceusage.serviceUsageAdmin"
```

> Ajusta estos roles según la política de **least privilege** de tu organización.  
> Para labs/sandbox, esto es suficiente y simple.

### 4.3. On the state bucket project

Si el bucket de state vive en `INFRA_PROJECT_ID`:

```bash
TF_STATE_BUCKET="tfstate-org-shared"

# Permiso para leer/escribir el tfstate
gcloud storage buckets add-iam-binding "gs://${TF_STATE_BUCKET}" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/storage.objectAdmin"
```

Si usas **CMEK** para el bucket, añade:

```bash
KMS_KEY_ID="projects/infra-shared/locations/us-central1/keyRings/tfstate-keyring/cryptoKeys/tfstate-key"

gcloud kms keys add-iam-policy-binding "$(basename "${KMS_KEY_ID}")" --keyring="tfstate-keyring" --location="us-central1" --project="infra-shared" --member="serviceAccount:${TF_SA_EMAIL}" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

(ajusta `project`/`location`/`keyRing`/`key` a tu caso real).

---

## 5. Create the Workload Identity Pool

Now create the **WIF pool** in the **INFRA project**:

```bash
gcloud iam workload-identity-pools create "${WIP_POOL_ID}" --project="${INFRA_PROJECT_ID}" --location="global" --display-name="${WIP_POOL_DISPLAY_NAME}"
```

Get the pool resource name:

```bash
gcloud iam workload-identity-pools describe "${WIP_POOL_ID}" --project="${INFRA_PROJECT_ID}" --location="global" --format="value(name)"
```

Example output:

```text
projects/123456789012/locations/global/workloadIdentityPools/github-pool
```

Note the **project number** (`123456789012`) – you need it for the provider and for the GitHub Actions variable.

---

## 6. Create the Workload Identity Provider (GitHub OIDC)

Create an **OIDC provider** that trusts GitHub Actions tokens from **your repo**:

> ⚠️ Display name must be <= 32 chars, so keep it short.

```bash
gcloud iam workload-identity-pools providers create-oidc "${WIP_PROVIDER_ID}" --project="${INFRA_PROJECT_ID}" --location="global" --workload-identity-pool="${WIP_POOL_ID}" --display-name="${WIP_PROVIDER_DISPLAY_NAME}" --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" --attribute-condition="assertion.repository == \"${GITHUB_REPO}\"" --issuer-uri="https://token.actions.githubusercontent.com"
```

This:

- Maps GitHub OIDC claims to GCP attributes
- Restricts usage to a **single GitHub repo**: `jagc108/gcp-infrastructure`

If you want to further restrict (e.g., only `refs/heads/main`), you can change the `attribute-condition`, for example:

```text
attribute.repository == "jagc108/gcp-infrastructure" &&
attribute.ref == "refs/heads/main"
```

---

## 7. Allow the pool to impersonate the Terraform SA

Now bind the **pool identities** to the TF SA with `roles/iam.workloadIdentityUser`.

1. Get the **pool full name**:

   ```bash
   WIP_POOL_FULL_NAME=$(gcloud iam workload-identity-pools describe "${WIP_POOL_ID}" --project="${INFRA_PROJECT_ID}" --location="global" --format="value(name)")

   echo "${WIP_POOL_FULL_NAME}"
   # e.g. projects/123456789012/locations/global/workloadIdentityPools/github-pool
   ```

2. Grant the binding:

   ```bash
   gcloud iam service-accounts add-iam-policy-binding "${TF_SA_EMAIL}" --project="${INFRA_PROJECT_ID}" --role="roles/iam.workloadIdentityUser" --member="principalSet://iam.googleapis.com/${WIP_POOL_FULL_NAME}/attribute.repository/${GITHUB_REPO}"
   ```

This allows **any GitHub Actions job** from that repo (and matching the provider condition) to impersonate the TF SA.

---

## 8. Values to use in GitHub Actions

You’ll need two important values in your workflow:

1. **Terraform SA email** → `TF_SA_EMAIL`, e.g.:

   ```text
   github-tf-prod@my-host-project.iam.gserviceaccount.com
   ```

2. **Workload Identity Provider resource name**, e.g.:

   ```text
   projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-actions-prod
   ```

Get it with:

```bash
gcloud iam workload-identity-pools providers describe "${WIP_PROVIDER_ID}" --project="${INFRA_PROJECT_ID}" --location="global" --workload-identity-pool="${WIP_POOL_ID}" --format="value(name)"
```

Example:

```text
projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-actions-prod
```

In GitHub **Environment `prod`** define:

- `GCP_TF_SERVICE_ACCOUNT` → `github-tf-prod@my-host-project.iam.gserviceaccount.com`
- `GCP_WIF_PROVIDER` → `projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-actions-prod`
- And other vars like:
  - `HOST_PROJECT_ID_PROD`
  - `SERVICE_PROJECT_ID_PROD`
  - `REGION_PROD`

---

## 9. Terraform plan workflow (GitHub Actions)

Example workflow file: `.github/workflows/terraform-plan-prod.yml`

```yaml
name: Terraform plan - Prod

on:
  pull_request:
    branches:
      - main
    paths:
      - "environments/prod/**"

env:
  TF_INPUT: "false"

permissions:
  id-token: write        # required for OIDC / WIF
  contents: read
  pull-requests: write

jobs:
  plan:
    environment: prod
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ./environments/prod

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud (WIF)
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
        run: |
          terraform validate
          echo "::set-output name=stdout::$(terraform validate -no-color)"

      - name: Terraform - Plan
        id: plan
        run: |
          terraform plan -out=plan.tmp
          terraform show -no-color plan.tmp >${GITHUB_WORKSPACE}/plan.out

      - name: Terraform - Show Plan in PR
        uses: actions/github-script@v8
        if: github.event_name == 'pull_request'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const run_url = process.env.GITHUB_SERVER_URL + '/' + process.env.GITHUB_REPOSITORY + '/actions/runs/' + process.env.GITHUB_RUN_ID
            const run_link = '<a href="' + run_url + '">Actions</a>.'
            const fs = require('fs')
            const plan_file = fs.readFileSync('plan.out', 'utf8')
            const plan = plan_file.length > 65000 ? plan_file.toString().substring(0, 65000) + " ..." : plan_file
            const truncated_message = plan_file.length > 65000 ? "Output is too long and was truncated. You can read full Plan in " + run_link + "<br /><br />" : ""
            const output = `#### Terraform Format and Style 🖌\`${{ steps.fmt.outcome }}\`
            #### Terraform Initialization ⚙️\`${{ steps.init.outcome }}\`
            #### Terraform Validation 🤖\`${{ steps.validate.outcome }}\`

            #### Terraform Plan 📖\`${{ steps.plan.outcome }}\`

            <details><summary>Show Plan</summary>

            \`\`\`

            ${plan}
            \`\`\`

            </details>
            ${truncated_message}

            *Pusher: @${{ github.actor }}, Workflow: \`${{ github.workflow }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })
```

---

## 10. Link from the main README

In your main `README.md` (in the repo root), add a link to this document, for example under the **CI/CD – GitHub Actions (Terraform Plan)** section:

```markdown
For a detailed, step‑by‑step guide on how to configure the Terraform Service Account and Workload Identity Federation for this workflow, see [README-ci-wif.md](README-ci-wif.md).
```

Name this file `README-ci-wif.md` and place it in the repo root so the relative link works as written above.
