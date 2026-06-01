#!/bin/bash
# ============================================================
#  Portfolio MCS — Kubernetes Deploy Script
#
#  Applies all manifests in the correct order.
#  Supports both Minikube (local) and production clusters.
#
#  Usage:
#    chmod +x k8s/deploy.sh
#
#    # Minikube (local):
#    ./k8s/deploy.sh --env local
#
#    # Production:
#    ./k8s/deploy.sh --env prod
#
#  Prerequisites:
#    - kubectl configured and pointing at your cluster
#    - Infisical operator installed on the cluster
#    - infisical-machine-identity secret created manually
#    - For local: minikube addons enable ingress metrics-server
#    - For prod:  cert-manager and nginx ingress controller installed
# ============================================================
set -euo pipefail

NAMESPACE="portfolio"
ENV="local"   # default

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
abort() { echo -e "${RED}[error]${NC} $*"; exit 1; }

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --env) ENV="$2"; shift 2 ;;
    *) abort "Unknown argument: $1" ;;
  esac
done

[[ "$ENV" == "local" || "$ENV" == "prod" ]] \
  || abort "--env must be 'local' or 'prod'"

info "Deploying to environment: $ENV"

# ── Preflight checks ─────────────────────────────────────
info "Running preflight checks …"

command -v kubectl &>/dev/null || abort "kubectl not found"
kubectl cluster-info &>/dev/null || abort "Cannot reach cluster — check your kubeconfig"

# Check Infisical operator CRD exists
kubectl get crd infisicalsecrets.secrets.infisical.com &>/dev/null \
  || abort "Infisical operator CRD not found.\nInstall it: kubectl apply -f https://raw.githubusercontent.com/Infisical/infisical/main/k8-operator/config/install/install.yaml"

# Check machine identity secret exists (the one manually created)
kubectl get secret infisical-machine-identity -n "$NAMESPACE" &>/dev/null 2>&1 \
  || abort "infisical-machine-identity secret not found in namespace '$NAMESPACE'.\nCreate it: kubectl create secret generic infisical-machine-identity --namespace $NAMESPACE --from-literal=clientId=... --from-literal=clientSecret=..."

info "Preflight checks passed ✅"

# ── 1. Namespace ─────────────────────────────────────────
info "Applying namespace …"
kubectl apply -f k8s/00-namespace.yaml

# ── 2. ConfigMap ─────────────────────────────────────────
info "Applying configmap …"
kubectl apply -f k8s/01-configmap.yaml

# ── 3. Infisical — create portfolio-secrets automatically ─
info "Applying InfisicalSecret (creates portfolio-secrets from Infisical) …"
kubectl apply -f k8s/infisical/02-infisical-secret.yaml

info "Waiting for Infisical operator to sync portfolio-secrets …"
for i in $(seq 1 30); do
  if kubectl get secret portfolio-secrets -n "$NAMESPACE" &>/dev/null 2>&1; then
    info "portfolio-secrets created by Infisical operator ✅"
    break
  fi
  echo "  waiting for Infisical sync … ($i/30)"
  sleep 5
  [[ $i -eq 30 ]] && abort "portfolio-secrets was not created after 150s.\nCheck InfisicalSecret status: kubectl describe infisicalsecret -n $NAMESPACE"
done

# ── 4. GHCR pull secret ───────────────────────────────────
kubectl get secret ghcr-pull-secret -n "$NAMESPACE" &>/dev/null 2>&1 \
  || abort "ghcr-pull-secret not found.\nCreate it: kubectl create secret docker-registry ghcr-pull-secret --namespace $NAMESPACE --docker-server=ghcr.io --docker-username=johnitopaisah --docker-password=YOUR_PAT --docker-email=johnitopaisah@gmail.com"

# ── 5. Policies ───────────────────────────────────────────
info "Applying policies …"
kubectl apply -f k8s/policies/01-pdb-api.yaml
kubectl apply -f k8s/policies/02-pdb-user-ui.yaml
kubectl apply -f k8s/policies/03-pdb-admin-ui.yaml
kubectl apply -f k8s/policies/04-network-policy.yaml
kubectl apply -f k8s/policies/05-resource-quota.yaml
kubectl apply -f k8s/policies/06-limit-range.yaml

# ── 6. Database ───────────────────────────────────────────
info "Applying database …"
kubectl apply -f k8s/db/01-pvc.yaml
kubectl apply -f k8s/db/02-service.yaml
kubectl apply -f k8s/db/03-configmap-schema.yaml
kubectl apply -f k8s/db/04-configmap-seed.yaml
kubectl apply -f k8s/db/05-statefulset.yaml

info "Waiting for database …"
kubectl rollout status statefulset/portfolio-db -n "$NAMESPACE" --timeout=120s

# ── 7. API ───────────────────────────────────────────────
info "Applying API …"
kubectl apply -f k8s/api/01-serviceaccount.yaml
kubectl apply -f k8s/api/02-service.yaml
kubectl apply -f k8s/api/03-deployment.yaml

info "Waiting for API …"
kubectl rollout status deployment/portfolio-api -n "$NAMESPACE" --timeout=120s

# ── 8. User UI ───────────────────────────────────────────
info "Applying user-ui …"
kubectl apply -f k8s/user-ui/01-serviceaccount.yaml
kubectl apply -f k8s/user-ui/02-service.yaml
kubectl apply -f k8s/user-ui/03-deployment.yaml

# ── 9. Admin UI ──────────────────────────────────────────
info "Applying admin-ui …"
kubectl apply -f k8s/admin-ui/01-serviceaccount.yaml
kubectl apply -f k8s/admin-ui/02-service.yaml
kubectl apply -f k8s/admin-ui/03-deployment.yaml

info "Waiting for frontends …"
kubectl rollout status deployment/portfolio-user-ui  -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/portfolio-admin-ui -n "$NAMESPACE" --timeout=120s

# ── 10. HPAs ─────────────────────────────────────────────
info "Applying HPAs …"
kubectl apply -f k8s/hpa/

# ── 11. Ingress ───────────────────────────────────────────
if [[ "$ENV" == "local" ]]; then
  info "Applying Minikube ingress (no TLS) …"
  kubectl apply -f k8s/ingress/01-ingress-minikube.yaml
  warn "Add these to /etc/hosts if not already done:"
  warn "  echo \"\$(minikube ip) portfolio.local api.portfolio.local admin.portfolio.local\" | sudo tee -a /etc/hosts"
else
  info "Applying cert-manager ClusterIssuer …"
  kubectl apply -f k8s/ingress/00-cert-manager.yaml
  info "Applying production ingress (TLS) …"
  kubectl apply -f k8s/ingress/02-ingress-production.yaml
fi

# ── Done ─────────────────────────────────────────────────
echo ""
info "All resources applied ✅"
echo ""
kubectl get pods -n "$NAMESPACE"
echo ""

if [[ "$ENV" == "local" ]]; then
  echo "  Local access (after /etc/hosts entry):"
  echo "    http://portfolio.local        → user-ui"
  echo "    http://api.portfolio.local    → api"
  echo "    http://admin.portfolio.local  → admin-ui"
else
  echo "  Production access (after DNS A records point to LoadBalancer IP):"
  echo "    https://johnisah.com          → user-ui"
  echo "    https://api.johnisah.com      → api"
  echo "    https://admin.johnisah.com    → admin-ui"
fi
