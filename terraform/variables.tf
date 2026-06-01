# ══════════════════════════════════════════════════════════════════════════════
# GCP
# ══════════════════════════════════════════════════════════════════════════════

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID where all resources will be created."
}

variable "gcp_region" {
  type        = string
  description = "GCP region for the VPC subnet, static IP, and VM (e.g. us-central1)."
}

variable "gcp_zone" {
  type        = string
  description = "GCP zone for the GCE instance (e.g. euro-west9-a). Must be within gcp_region."
}

variable "gcp_credentials_file" {
  type        = string
  description = "Absolute path to the Terraform service account JSON key file. Must be outside the repo."
}

variable "machine_type" {
  type        = string
  description = "GCE machine type for devops-instance."
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for devops-instance."
  default     = 100
}

variable "ssh_source_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to SSH into devops-instance on port 22. Restrict to your IP."
  default     = ["128.78.214.46/32"]
}

# ══════════════════════════════════════════════════════════════════════════════
# SSH
# ══════════════════════════════════════

variable "ssh_public_key_path" {
  type        = string
  description = "Absolute path to the SSH public key injected into devops-instance as the isahjohna user."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Absolute path to the SSH private key used by remote-exec to connect to the VM."
}

# ══════════════════════════════════════════════════════════════════════════════
# Cloudflare
# ══════════════════════════════════════════════════════════════════════════════

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token scoped to DNS:Edit on the johnisah.org zone only."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for johnisah.org. Found in the domain overview sidebar."
}

# ══════════════════════════════════════════════════════════════════════════════
# Infisical
# ══════════════════════════════════════════════════════════════════════════════

variable "infisical_ecommerce_client_id" {
  type        = string
  sensitive   = true
  description = "Infisical machine identity client ID for the ecommerce namespace."
}

variable "infisical_ecommerce_client_secret" {
  type        = string
  sensitive   = true
  description = "Infisical machine identity client secret for the ecommerce namespace."
}

variable "infisical_portfolio_client_id" {
  type        = string
  sensitive   = true
  description = "Infisical machine identity client ID for the portfolio namespace."
}

variable "infisical_portfolio_client_secret" {
  type        = string
  sensitive   = true
  description = "Infisical machine identity client secret for the portfolio namespace."
}

# ══════════════════════════════════════════════════════════════════════════════
# ArgoCD
# ══════════════════════════════════════════════════════════════════════════════

variable "argocd_repo_url" {
  type        = string
  description = "HTTPS clone URL of this Git repository used by ArgoCD to sync manifests."
}

variable "argocd_target_revision" {
  type        = string
  description = "Git branch or tag ArgoCD tracks for manifest sync."
  default     = "develop"
}

# ══════════════════════════════════════════════════════════════════════════════
# Tool versions — pinned for reproducibility
# ══════════════════════════════════════════════════════════════════════════════ 

variable "minikube_version" {
  type        = string
  description = "Minikube release version to install on the VM. Check https://github.com/kubernetes/minikube/releases for latest."
  default     = "v1.38.1"
}

variable "k8s_version" {
  type = string
  # Pinned to v1.34.2 — the version tested with the ArgoCD release in argocd-values.yaml.
  # Latest stable Kubernetes is v1.36.1 but upgrading requires re-validating ArgoCD
  # compatibility. Update only after testing. Check: https://kubernetes.io/releases/
  description = "Kubernetes version for the Minikube cluster. Must be supported by the chosen minikube_version."
  default     = "v1.34.2"
}

variable "helm_version" {
  type = string
  # Using latest Helm v3 — NOT v4. Helm v4 introduced breaking changes and all
  # existing chart configurations in bootstrapping/ target the v3 API.
  # Check latest v3: https://github.com/helm/helm/releases
  description = "Helm CLI version to install on the VM. Use v3.x — Helm v4 has breaking changes."
  default     = "v3.21.0"
}

variable "cert_manager_version" {
  type        = string
  description = "cert-manager Helm chart version. Check https://github.com/cert-manager/cert-manager/releases for latest."
  default     = "v1.20.2"
}
