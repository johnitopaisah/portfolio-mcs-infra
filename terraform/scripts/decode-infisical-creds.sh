#!/usr/bin/env bash
# =============================================================================
# decode-infisical-creds.sh — decode Infisical machine identity credentials
#
# Reads the base64-encoded clientId and clientSecret from the bootstrapping
# YAML files and prints them as plain text ready to paste into terraform.tfvars.
#
# Usage:
#   ./terraform/scripts/decode-infisical-creds.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ECOMMERCE_YAML="${REPO_ROOT}/bootstrapping/infisical-auth-secret-ecommerce.yaml"
PORTFOLIO_YAML="${REPO_ROOT}/bootstrapping/infisical-auth-secret-portfolio.yaml"

# ── Check files exist ─────────────────────────────────────────────────────────
missing=0
for f in "${ECOMMERCE_YAML}" "${PORTFOLIO_YAML}"; do
  if [[ ! -f "$f" ]]; then
    echo "  ✗  Not found: $f"
    echo "     These files are gitignored. Ensure you have them locally or"
    echo "     get fresh credentials from app.infisical.com → Access Control"
    (( missing++ )) || true
  fi
done
[[ $missing -gt 0 ]] && exit 1

# ── Decode ────────────────────────────────────────────────────────────────────
decode_field() {
  local file="$1"
  local field="$2"
  grep "${field}:" "$file" \
    | tail -1 \
    | awk '{print $2}' \
    | tr -d '"' \
    | base64 --decode \
    | tr -d '\n'
}

ECOMMERCE_CLIENT_ID=$(decode_field "${ECOMMERCE_YAML}" "clientId")
ECOMMERCE_CLIENT_SECRET=$(decode_field "${ECOMMERCE_YAML}" "clientSecret")
PORTFOLIO_CLIENT_ID=$(decode_field "${PORTFOLIO_YAML}" "clientId")
PORTFOLIO_CLIENT_SECRET=$(decode_field "${PORTFOLIO_YAML}" "clientSecret")

# ── Output ────────────────────────────────────────────────────────────────────
echo ""
echo "  ┌──────────────────────────────────────────────────────────────────┐"
echo "  │  Copy the following into terraform/terraform.tfvars:             │"
echo "  └──────────────────────────────────────────────────────────────────┘"
cat <<TFVARS

infisical_ecommerce_client_id     = "${ECOMMERCE_CLIENT_ID}"
infisical_ecommerce_client_secret = "${ECOMMERCE_CLIENT_SECRET}"

infisical_portfolio_client_id     = "${PORTFOLIO_CLIENT_ID}"
infisical_portfolio_client_secret = "${PORTFOLIO_CLIENT_SECRET}"

TFVARS

echo "  These values are decoded from:"
echo "    bootstrapping/infisical-auth-secret-ecommerce.yaml"
echo "    bootstrapping/infisical-auth-secret-portfolio.yaml"
echo ""
echo "  Alternatively, get fresh credentials from:"
echo "    app.infisical.com → Project → Access Control → Machine Identities"
echo ""
