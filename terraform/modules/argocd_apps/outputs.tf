output "complete" {
  value       = null_resource.argocd_apps.id
  description = "Non-null once ArgoCD Application CRs have been applied."
}
