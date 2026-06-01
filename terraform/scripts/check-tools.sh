#!/usr/bin/env bash
# =============================================================================
# check-tools.sh — verify all required tools are installed before terraform init
#
# Usage: ./terraform/scripts/check-tools.sh
# =============================================================================
set -euo pipefail

PASS="✓"
FAIL="✗"
WARN="!"
errors=0

check() {
  local name="$1"
  local cmd="$2"
  local min_version="$3"
  local actual

  if ! command -v "${cmd%% *}" &>/dev/null; then
    echo "  ${FAIL}  $name — NOT INSTALLED"
    (( errors++ )) || true
    return
  fi

  actual=$(eval "$cmd" 2>/dev/null | head -1)
  echo "  ${PASS}  $name — $actual"
}

echo ""
echo "══════════════════════════════════════════"
echo "  Portfolio MCS — Pre-flight tool check"
echo "══════════════════════════════════════════"
echo ""
echo "── Required tools ───────────────────────"

check "Terraform" "terraform version" "1.6"
check "gcloud CLI" "gcloud version" ""

echo ""
echo "── gcloud authentication ────────────────"

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "  ${FAIL}  No active gcloud account — run: gcloud auth login"
  (( errors++ )) || true
else
  echo "  ${PASS}  Active account: ${ACTIVE_ACCOUNT}"
fi

ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ -z "${ACTIVE_PROJECT}" || "${ACTIVE_PROJECT}" == "(unset)" ]]; then
  echo "  ${WARN}  No default project set — run: gcloud config set project YOUR_PROJECT_ID"
else
  echo "  ${PASS}  Default project: ${ACTIVE_PROJECT}"
fi

echo ""
echo "── Terraform credentials ─────────────────"

if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "  ${WARN}  GOOGLE_APPLICATION_CREDENTIALS is not set"
  echo "       Set it in ~/.zshrc or ~/.bashrc:"
  echo "       export GOOGLE_APPLICATION_CREDENTIALS=/path/to/terraform-sa-key.json"
else
  if [[ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    echo "  ${PASS}  GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}"
  else
    echo "  ${FAIL}  GOOGLE_APPLICATION_CREDENTIALS set but file not found: ${GOOGLE_APPLICATION_CREDENTIALS}"
    (( errors++ )) || true
  fi
fi

echo ""

if [[ $errors -gt 0 ]]; then
  echo "  ${FAIL}  ${errors} issue(s) found — fix before running terraform init"
  exit 1
else
  echo "  ${PASS}  All checks passed — ready to run terraform init"
fi
echo ""
