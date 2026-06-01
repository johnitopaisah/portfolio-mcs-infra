# ── GCP ──────────────────────────────────────────────────────────────────────────
# Authenticates using the dedicated Terraform service account key file.
# The key file must live outside the repository — store it at ~/.gcp/ or similar.
provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  zone        = var.gcp_zone
  credentials = file(var.gcp_credentials_file)
}

# ── Cloudflare ───────────────────────────────────────────────────────────────────
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── Kubernetes ───────────────────────────────────────────────────────────────────
# config_path points to the kubeconfig written by module.cluster_init.
# This provider is only invoked during Stage 3 (full apply) — when the file exists.
# During Stage 1 and Stage 2 (-target applies), no kubernetes resources are planned
# so the provider does not attempt to connect even if the file is absent.
provider "kubernetes" {
  config_path = local.kubeconfig_path
}

# ── Helm ─────────────────────────────────────────────────────────────────────────
# Same kubeconfig as the kubernetes provider — both talk to the same Minikube cluster.
provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}
