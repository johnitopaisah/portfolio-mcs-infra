output "complete" {
  value       = null_resource.cluster_bootstrap.id
  description = "Non-null once cluster_bootstrap has run. Used as a depends_on anchor by argocd_apps."
}

output "argocd_url" {
  value       = "https://${var.argocd_domain}"
  description = "ArgoCD web UI URL."
}
