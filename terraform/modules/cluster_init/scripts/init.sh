#!/usr/bin/env bash
# =============================================================================
# init.sh — Cluster initialisation script
#
# Runs via Terraform remote-exec (Block 2) as isahjohna.
# By the time this script runs, Docker is already installed and isahjohna is
# already in the docker group (done in Block 1 remote-exec). The SSH session
# for Block 2 is a fresh login that picks up the docker group automatically,
# so all minikube commands can reach the Docker socket without sudo or sg.
#
# Variables injected as environment variables by the remote-exec inline block:
#   MINIKUBE_VERSION, K8S_VERSION, HELM_VERSION
#
# Idempotent: safe to re-run. Each section checks before acting.
# Output is tee'd to /tmp/init.log for post-run inspection on the VM.
# =============================================================================
set -euo pipefail

# Self-logging: all output goes to the terminal (captured by Terraform)
# AND to /tmp/init.log on the VM for manual debugging.
exec > >(tee /tmp/init.log) 2>&1

# ── Variables ─────────────────────────────────────────────────────────────────
MINIKUBE_VERSION="${MINIKUBE_VERSION:-v1.38.1}"
K8S_VERSION="${K8S_VERSION:-v1.34.2}"
HELM_VERSION="${HELM_VERSION:-v3.21.0}"
PROFILE="devops-minikube"
NODES=2
CPUS_PER_NODE=2
MEMORY_PER_NODE=4096
DISK_SIZE="20g"

log() {
  echo
  echo "=================================================="
  echo "==> $*"
  echo "=================================================="
}

# ── 1. Minikube ──────────────────────────────────────────────────────────────
if command -v minikube &>/dev/null && minikube version 2>/dev/null | grep -q "${MINIKUBE_VERSION}"; then
  log "Minikube ${MINIKUBE_VERSION} already installed — skipping"
else
  log "Installing Minikube ${MINIKUBE_VERSION}"
  curl -fsSL \
    "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64" \
    -o /tmp/minikube
  sudo install -o root -g root -m 0755 /tmp/minikube /usr/local/bin/minikube
  rm -f /tmp/minikube
fi
minikube version

# ── 2. kubectl ───────────────────────────────────────────────────────────────
if command -v kubectl &>/dev/null && kubectl version --client 2>/dev/null | grep -q "${K8S_VERSION}"; then
  log "kubectl ${K8S_VERSION} already installed — skipping"
else
  log "Installing kubectl ${K8S_VERSION}"
  curl -fsSL \
    "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" \
    -o /tmp/kubectl
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi
kubectl version --client

# ── 3. Helm ──────────────────────────────────────────────────────────────────
if command -v helm &>/dev/null && helm version --short 2>/dev/null | grep -q "${HELM_VERSION}"; then
  log "Helm ${HELM_VERSION} already installed — skipping"
else
  log "Installing Helm ${HELM_VERSION}"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    -o /tmp/get-helm.sh
  chmod +x /tmp/get-helm.sh
  DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
  rm -f /tmp/get-helm.sh
fi
helm version --short

# ── 4. Helm repos ────────────────────────────────────────────────────────────
log "Adding Helm repositories"
helm repo add argo                  https://argoproj.github.io/argo-helm                          || true
helm repo add cert-manager          https://charts.jetstack.io                                    || true
helm repo add infisical-helm-charts https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/ || true
helm repo add traefik               https://traefik.github.io/charts                              || true
helm repo update

# ── 5. Start Minikube ────────────────────────────────────────────────────────
# No sg docker needed — this SSH session already has the docker group active
# because Block 1 ran usermod and this is a fresh SSH connection.
if minikube status -p "${PROFILE}" 2>/dev/null | grep -q "^host: Running"; then
  log "Minikube profile '${PROFILE}' already running — skipping start"
else
  log "Starting Minikube profile '${PROFILE}'"
  minikube start \
    --profile="${PROFILE}" \
    --driver=docker \
    --container-runtime=containerd \
    --kubernetes-version="${K8S_VERSION}" \
    --nodes="${NODES}" \
    --cpus="${CPUS_PER_NODE}" \
    --memory="${MEMORY_PER_NODE}" \
    --disk-size="${DISK_SIZE}" \
    --embed-certs=true
fi

# Set the active kubectl context.
kubectl config use-context "${PROFILE}"

# ── 6. Minikube addons ───────────────────────────────────────────────────────
log "Enabling Minikube addons"
minikube -p "${PROFILE}" addons enable metrics-server       || true
minikube -p "${PROFILE}" addons enable default-storageclass  || true
minikube -p "${PROFILE}" addons enable storage-provisioner   || true

# ── 7. Wait for nodes to be Ready ────────────────────────────────────────────
log "Waiting for all nodes to be Ready (timeout 5 min)"
kubectl --context="${PROFILE}" wait node \
  --all --for=condition=Ready --timeout=300s

kubectl --context="${PROFILE}" get nodes

minikube ssh -p devops-minikube -n devops-minikube \
  "sudo mkdir -p /tmp/hostpath-provisioner/portfolio/portfolio-db-pvc"

# ── 8. NGINX ─────────────────────────────────────────────────────────────────
log "Installing and configuring NGINX"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx

# Remove Ubuntu's default site — it also listens on port 80 and would conflict
# with our custom server block when sites-enabled/* is included.
sudo rm -f /etc/nginx/sites-enabled/default

# Determine the actual Minikube Docker bridge IP — usually 192.168.49.2 but
# always read it dynamically in case the subnet was reassigned.
MINIKUBE_IP=$(minikube -p "${PROFILE}" ip)
log "Minikube IP: ${MINIKUBE_IP}"

# Install and patch nginx.conf (uploaded to /tmp/nginx.conf by Terraform).
sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf
sudo sed -i "s/192\.168\.49\.2/${MINIKUBE_IP}/g" /etc/nginx/nginx.conf

sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

log "Cluster initialisation complete"
echo "Profile     : ${PROFILE}"
echo "Minikube IP : ${MINIKUBE_IP}"
kubectl --context="${PROFILE}" get nodes
