# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1 — GCP Infrastructure
# Apply with: terraform apply -target=module.gcp_infra
#
# Creates: VPC, subnet, firewall rules, static IP, VM service account,
#          and the devops-instance GCE instance.
#
# Output to note after this stage:
#   - vm_static_ip (shown in terraform output)
#   - Verify SSH: ssh -i <private_key> isahjohna@<static_ip>
# ══════════════════════════════════════════════════════════════════════════════

module "gcp_infra" {
  source = "./modules/gcp_infra"

  project             = var.gcp_project_id
  region              = var.gcp_region
  zone                = var.gcp_zone
  machine_type        = var.machine_type
  disk_size_gb        = var.disk_size_gb
  ssh_public_key_path = var.ssh_public_key_path
  ssh_source_ranges   = var.ssh_source_ranges
  common_labels       = local.common_labels
}


# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2 — Cloudflare DNS + Cluster Initialisation (parallel)
# Apply with: terraform apply -target=module.cloudflare_dns -target=module.cluster_init
#
# cloudflare_dns: creates all 8 A/CNAME records pointing to the static IP.
# cluster_init:   SSHes into the VM, installs tooling, starts Minikube,
#                 configures NGINX, and writes the patched kubeconfig locally.
#
# Both modules depend on module.gcp_infra (the static IP) and are otherwise
# independent — Terraform runs them concurrently.
#
# After this stage:
#   - Verify DNS:       dig +short johnisah.org
#   - Verify cluster:  kubectl --kubeconfig=.kube/devops-minikube.yaml get nodes
# ══════════════════════════════════════════════════════════════════════════════

module "cloudflare_dns" {
  source = "./modules/cloudflare_dns"

  zone_id = var.cloudflare_zone_id
  vm_ip   = module.gcp_infra.static_ip

  depends_on = [module.gcp_infra]
}

module "cluster_init" {
  source = "./modules/cluster_init"

  vm_ip                = module.gcp_infra.static_ip
  ssh_private_key_path = var.ssh_private_key_path
  minikube_version     = var.minikube_version
  k8s_version          = var.k8s_version
  helm_version         = var.helm_version
  nginx_conf_path      = "${path.root}/../bootstrapping/nginx.conf"

  depends_on = [module.gcp_infra]
}


# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3 — Cluster Bootstrap + Workload Seed (full apply)
# Apply with: terraform apply
#
# cluster_bootstrap: namespaces, cert-manager, Traefik, Infisical, ArgoCD.
# argocd_apps:       seeds ArgoCD Application CRs — ArgoCD takes over from here.
# ══════════════════════════════════════════════════════════════════════════════

module "cluster_bootstrap" {
  source = "./modules/cluster_bootstrap"

  vm_ip                = module.gcp_infra.static_ip
  ssh_private_key_path = var.ssh_private_key_path
  cert_manager_version = var.cert_manager_version
  argocd_domain        = "argocd-deploy.johnisah.org"

  infisical_ecommerce_client_id     = var.infisical_ecommerce_client_id
  infisical_ecommerce_client_secret = var.infisical_ecommerce_client_secret
  infisical_portfolio_client_id     = var.infisical_portfolio_client_id
  infisical_portfolio_client_secret = var.infisical_portfolio_client_secret

  cluster_issuer_yaml_path             = "${path.root}/../bootstrapping/cluster-issuer.yaml"
  argocd_values_yaml_path              = "${path.root}/../bootstrapping/argocd-values.yaml"
  argocd_ingress_yaml_path             = "${path.root}/../bootstrapping/argocd-ingress-traefik.yaml"
  infisical_secret_ecommerce_yaml_path = "${path.root}/../bootstrapping/infisical-secret-ecommerce.yaml"
  infisical_secret_portfolio_yaml_path = "${path.root}/../bootstrapping/infisical-secret-porfolio.yaml"

  depends_on = [module.cluster_init]
}

module "argocd_apps" {
  source = "./modules/argocd_apps"

  vm_ip                    = module.gcp_infra.static_ip
  ssh_private_key_path     = var.ssh_private_key_path
  argocd_project_yaml_path = "${path.root}/../k8s/argocd/project.yaml"
  argocd_root_app_yaml_path = "${path.root}/../k8s/argocd/root-app.yaml"

  depends_on = [module.cluster_bootstrap]
}
