variable "vm_ip" {
  type        = string
  description = "Static external IP of devops-instance."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Absolute path to the SSH private key for the isahjohna user."
}

variable "cert_manager_version" {
  type        = string
  description = "cert-manager Helm chart version (e.g. v1.20.2)."
}

variable "argocd_domain" {
  type        = string
  description = "Public domain for the ArgoCD server (e.g. argocd-deploy.johnisah.org)."
  default     = "argocd-deploy.johnisah.org"
}

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

# ── Paths to bootstrapping YAML files (local machine) ────────────────────────
# These files live in bootstrapping/ in the repo root. Some are gitignored
# (infisical*) so they must exist on the local machine running terraform apply.

variable "cluster_issuer_yaml_path" {
  type        = string
  description = "Local path to bootstrapping/cluster-issuer.yaml."
}

variable "argocd_values_yaml_path" {
  type        = string
  description = "Local path to bootstrapping/argocd-values.yaml."
}

variable "argocd_ingress_yaml_path" {
  type        = string
  description = "Local path to bootstrapping/argocd-ingress-traefik.yaml."
}

variable "infisical_secret_ecommerce_yaml_path" {
  type        = string
  description = "Local path to bootstrapping/infisical-secret-ecommerce.yaml."
}

variable "infisical_secret_portfolio_yaml_path" {
  type        = string
  description = "Local path to bootstrapping/infisical-secret-porfolio.yaml."
}
