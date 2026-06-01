#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — installs cluster-level components
#
# Order: Traefik → cert-manager → ClusterIssuer → Infisical → ArgoCD → Ingress
#
# Traefik is installed FIRST because the Let's Encrypt ClusterIssuer uses
# ingressClassName: traefik for HTTP-01 challenges. cert-manager validates the
# solver at registration time, so Traefik must exist before the ClusterIssuer
# is applied.
#
# Sensitive Infisical credentials are loaded from /tmp/.bootstrap_env
# (written by Terraform file provisioner) and deleted on completion.
#
# Non-sensitive variables injected via environment by the remote-exec block:
#   CERT_MANAGER_VERSION, ARGOCD_DOMAIN
# =============================================================================
set -euo pipefail
exec > >(tee /tmp/bootstrap.log) 2>&1

# Load sensitive credentials — file is deleted at the end of this script.
# shellcheck source=/dev/null
source /tmp/.bootstrap_env

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.2}"
ARGOCD_DOMAIN="${ARGOCD_DOMAIN:-argocd-deploy.johnisah.org}"
ARGOCD_RELEASE="argocd-deploy"
PROFILE="devops-minikube"

log() {
  echo
  echo "=================================================="
  echo "==> $*"
  echo "=================================================="
}

kubectl config use-context "${PROFILE}"

# ── 0. Refresh Helm chart index ──────────────────────────────────────────────
# Repos were added in init.sh. Update the index here so bootstrap always has
# the latest chart metadata, even if re-run days after init.
log "Refreshing Helm chart index"
helm repo update

# ── 1. Namespaces ────────────────────────────────────────────────────────────
log "Creating namespaces"
for ns in traefik argocd cert-manager infisical ecommerce portfolio monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# ── 2. Traefik ───────────────────────────────────────────────────────────────
# Installed BEFORE cert-manager/ClusterIssuer because the ClusterIssuer HTTP-01
# solver references ingressClassName: traefik. cert-manager validates the solver
# at ClusterIssuer registration time and needs Traefik to already exist.
log "Installing Traefik (NodePort 30080 / 30443)"
# In Traefik chart v40+, the service type is nested under service.spec.type,
# not service.type. Using service.type silently fails and defaults to LoadBalancer,
# which causes helm --wait to hang forever waiting for an external IP in Minikube.
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set service.spec.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --wait \
  --timeout=300s

kubectl rollout status deploy/traefik -n traefik --timeout=300s

# ── 3. cert-manager ──────────────────────────────────────────────────────────
log "Installing cert-manager ${CERT_MANAGER_VERSION}"
helm upgrade --install cert-manager cert-manager/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait \
  --timeout=300s

kubectl rollout status deploy/cert-manager            -n cert-manager --timeout=300s
kubectl rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=300s
kubectl rollout status deploy/cert-manager-webhook    -n cert-manager --timeout=300s

# ── 4. ClusterIssuer ─────────────────────────────────────────────────────────
# Applied after both cert-manager AND Traefik are running.
log "Creating Let's Encrypt ClusterIssuers"
kubectl apply -f /tmp/cluster-issuer.yaml

log "Waiting for letsencrypt-prod ClusterIssuer to be Ready"
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-prod --timeout=300s

# ── 5. Infisical secrets operator ────────────────────────────────────────────
log "Installing Infisical secrets operator"
helm upgrade --install infisical infisical-helm-charts/secrets-operator \
  --namespace infisical \
  --create-namespace \
  --set installCRDs=true \
  --wait \
  --timeout=300s

# Belt-and-suspenders: explicitly wait for the operator deployment to be
# Available. We use --all here because the exact deployment name is chart-
# version dependent. The outer 'helm --wait' already ensures pods are running,
# so this is a quick confirmation, not a long wait.
kubectl wait deploy --all -n infisical \
  --for=condition=Available \
  --timeout=120s

# ── 6. Infisical auth secrets ────────────────────────────────────────────────
log "Creating Infisical machine identity secrets"
kubectl create secret generic infisical-machine-identity \
  --namespace ecommerce \
  --from-literal=clientId="${INFISICAL_ECOMMERCE_CLIENT_ID}" \
  --from-literal=clientSecret="${INFISICAL_ECOMMERCE_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic infisical-machine-identity \
  --namespace portfolio \
  --from-literal=clientId="${INFISICAL_PORTFOLIO_CLIENT_ID}" \
  --from-literal=clientSecret="${INFISICAL_PORTFOLIO_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ── 7. InfisicalSecret CRs ───────────────────────────────────────────────────
# Applied only after the operator is fully ready (CRDs registered in step 5).
log "Applying InfisicalSecret CRs"
kubectl apply -f /tmp/infisical-secret-ecommerce.yaml
kubectl apply -f /tmp/infisical-secret-porfolio.yaml

# ── 8. ArgoCD ────────────────────────────────────────────────────────────────
log "Installing ArgoCD release '${ARGOCD_RELEASE}'"
helm upgrade --install "${ARGOCD_RELEASE}" argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set global.domain="${ARGOCD_DOMAIN}" \
  -f /tmp/argocd-values.yaml \
  --wait \
  --timeout=600s

kubectl rollout status deploy/"${ARGOCD_RELEASE}"-server                     -n argocd --timeout=300s
kubectl rollout status deploy/"${ARGOCD_RELEASE}"-repo-server                -n argocd --timeout=300s
kubectl rollout status deploy/"${ARGOCD_RELEASE}"-applicationset-controller  -n argocd --timeout=300s
kubectl rollout status deploy/"${ARGOCD_RELEASE}"-notifications-controller   -n argocd --timeout=300s
kubectl rollout status deploy/"${ARGOCD_RELEASE}"-redis                      -n argocd --timeout=300s
kubectl rollout status deploy/"${ARGOCD_RELEASE}"-dex-server                 -n argocd --timeout=300s
kubectl rollout status statefulset/"${ARGOCD_RELEASE}"-application-controller -n argocd --timeout=300s

# ── 9. ArgoCD ingress ────────────────────────────────────────────────────────
log "Applying ArgoCD ingress"
# The source file may still reference .johnisah.com — patch to .org before
# applying. The sed output is piped directly to kubectl with no temp file.
sed 's/\.johnisah\.com/.johnisah.org/g' /tmp/argocd-ingress-traefik.yaml \
  | kubectl apply -f -

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -f /tmp/.bootstrap_env

log "Cluster bootstrap complete"
echo "ArgoCD URL : https://${ARGOCD_DOMAIN}"
echo ""
echo "Get admin password:"
echo "  kubectl -n argocd get secret argocd-deploy-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode && echo"
