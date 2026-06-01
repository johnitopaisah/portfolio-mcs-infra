#!/usr/bin/env bash
# =============================================================================
# setup-gcp-prereqs.sh — one-shot GCP project bootstrap for Terraform
#
# What this script does (all idempotent — safe to re-run):
#   1. Signs in to gcloud (if needed)
#   2. Creates the GCP project
#   3. Pauses for you to enable billing in the browser (cannot be automated)
#   4. Enables required GCP APIs
#   5. Creates the Terraform service account
#   6. Grants all required IAM roles to the SA
#   7. Creates and versions the GCS state bucket
#   8. Grants the SA access to the bucket
#   9. Downloads the SA key to ~/.gcp/
#  10. Patches terraform/backend.tf with the real bucket name
#  11. Prints the GCP block for terraform.tfvars
#
# Usage:
#   ./terraform/scripts/setup-gcp-prereqs.sh <PROJECT_ID> [REGION] [ZONE]
#
# Examples:
#   ./terraform/scripts/setup-gcp-prereqs.sh portfolio-mcs-prod
#   ./terraform/scripts/setup-gcp-prereqs.sh portfolio-mcs-prod europe-west9 europe-west9-a
# =============================================================================
set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <PROJECT_ID> [REGION] [ZONE]"
  echo "  PROJECT_ID  — globally unique GCP project ID (e.g. portfolio-mcs-prod)"
  echo "  REGION      — GCP region (default: europe-west9)"
  echo "  ZONE        — GCP zone  (default: <REGION>-a)"
  exit 1
fi

PROJECT_ID="$1"
REGION="${2:-europe-west9}"
ZONE="${3:-${REGION}-a}"

SA_NAME="terraform-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-tfstate"
KEY_DIR="${HOME}/.gcp"
KEY_PATH="${KEY_DIR}/${PROJECT_ID}-terraform-sa-key.json"

# Resolve paths relative to this script (works regardless of CWD)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKEND_TF="${REPO_ROOT}/terraform/backend.tf"

log()  { echo; echo "══ $* ══"; }
ok()   { echo "  ✓  $*"; }
info() { echo "  →  $*"; }

# ── 1. gcloud authentication ──────────────────────────────────────────────────
log "Step 1 — gcloud authentication"

ACTIVE=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [[ -z "${ACTIVE}" ]]; then
  info "No active account found — opening browser for login"
  gcloud auth login
else
  ok "Already authenticated as: ${ACTIVE}"
fi

# ── 2. Create GCP project ─────────────────────────────────────────────────────
log "Step 2 — GCP project"

if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
  ok "Project '${PROJECT_ID}' already exists — skipping creation"
else
  info "Creating project '${PROJECT_ID}'"
  gcloud projects create "${PROJECT_ID}" --name="Portfolio MCS"
  ok "Project created"
fi

gcloud config set project "${PROJECT_ID}"
ok "Default project set to ${PROJECT_ID}"

# ── 3. Billing ────────────────────────────────────────────────────────────────
log "Step 3 — Billing (manual)"

BILLING=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || echo "false")
if [[ "${BILLING}" == "True" ]]; then
  ok "Billing already enabled"
else
  echo ""
  echo "  ┌──────────────────────────────────────────────────────────────┐"
  echo "  │  MANUAL STEP REQUIRED                                        │"
  echo "  │                                                              │"
  echo "  │  Billing cannot be enabled via the CLI without an            │"
  echo "  │  existing billing account ID. Open this URL in your          │"
  echo "  │  browser and link a billing account to the project:          │"
  echo "  │                                                              │"
  echo "  │  https://console.cloud.google.com/billing/projects           │"
  echo "  │                                                              │"
  echo "  └──────────────────────────────────────────────────────────────┘"
  echo ""
  read -r -p "  Press Enter once billing is enabled to continue... "
fi

# ── 4. Enable required APIs ───────────────────────────────────────────────────
log "Step 4 — Enabling GCP APIs"

APIS=(
  compute.googleapis.com
  storage.googleapis.com
  iam.googleapis.com
  cloudresourcemanager.googleapis.com
)

for api in "${APIS[@]}"; do
  if gcloud services list --enabled --filter="name:${api}" --format="value(name)" 2>/dev/null | grep -q "${api}"; then
    ok "${api} already enabled"
  else
    info "Enabling ${api}"
    gcloud services enable "${api}"
    ok "${api} enabled"
  fi
done

# ── 5. Terraform service account ─────────────────────────────────────────────
log "Step 5 — Terraform service account"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  ok "Service account ${SA_EMAIL} already exists"
else
  info "Creating service account ${SA_NAME}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Terraform Service Account" \
    --project="${PROJECT_ID}"
  ok "Service account created"
fi

# ── 6. IAM roles ─────────────────────────────────────────────────────────────
log "Step 6 — Granting IAM roles"

ROLES=(
  "roles/compute.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
  "roles/storage.admin"
)

for role in "${ROLES[@]}"; do
  info "Granting ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None \
    --quiet
  ok "${role} granted"
done

# ── 7. GCS state bucket ───────────────────────────────────────────────────────
log "Step 7 — GCS state bucket"

if gcloud storage buckets describe "gs://${BUCKET_NAME}" &>/dev/null; then
  ok "Bucket gs://${BUCKET_NAME} already exists"
else
  info "Creating bucket gs://${BUCKET_NAME} in ${REGION}"
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
  ok "Bucket created"
fi

gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning
ok "Versioning enabled"

# ── 8. Grant SA access to bucket ─────────────────────────────────────────────
log "Step 8 — Bucket IAM"

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin" \
  --quiet
ok "roles/storage.objectAdmin granted to ${SA_EMAIL} on bucket"

# ── 9. Download SA key ────────────────────────────────────────────────────────
log "Step 9 — Service account key"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [[ -f "${KEY_PATH}" ]]; then
  ok "Key already exists at ${KEY_PATH}"
else
  info "Downloading key to ${KEY_PATH}"
  gcloud iam service-accounts keys create "${KEY_PATH}" \
    --iam-account="${SA_EMAIL}"
  chmod 600 "${KEY_PATH}"
  ok "Key saved to ${KEY_PATH}"
fi

# ── 10. Patch backend.tf ──────────────────────────────────────────────────────
log "Step 10 — Patching terraform/backend.tf"

if [[ -f "${BACKEND_TF}" ]]; then
  # Replace the bucket placeholder with the real bucket name
  sed -i.bak \
    "s|bucket = \".*-tfstate\"|bucket = \"${BUCKET_NAME}\"|g" \
    "${BACKEND_TF}"
  rm -f "${BACKEND_TF}.bak"
  ok "backend.tf updated with bucket = \"${BUCKET_NAME}\""
else
  echo "  !  backend.tf not found at ${BACKEND_TF} — update it manually"
fi

# ── 11. Print terraform.tfvars GCP block ─────────────────────────────────────
log "Done — add these values to terraform/terraform.tfvars"

echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │  Copy the following into terraform/terraform.tfvars:            │"
echo "  └─────────────────────────────────────────────────────────────────┘"
cat <<TFVARS

gcp_project_id       = "${PROJECT_ID}"
gcp_region           = "${REGION}"
gcp_zone             = "${ZONE}"
gcp_credentials_file = "${KEY_PATH}"

TFVARS

echo "  Also add to ~/.zshrc (or ~/.bashrc) and re-source it:"
echo ""
echo "    export GOOGLE_APPLICATION_CREDENTIALS=${KEY_PATH}"
echo ""
echo "  Then run:"
echo "    source ~/.zshrc"
echo "    cd terraform && terraform init"
echo ""
