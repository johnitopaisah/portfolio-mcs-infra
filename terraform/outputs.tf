# ── Stage 1 outputs ──────────────────────────────────────────────────────────────

output "vm_static_ip" {
  value       = module.gcp_infra.static_ip
  description = "Static external IP address of devops-instance. Point all DNS records here."
}

output "vm_instance_name" {
  value       = module.gcp_infra.instance_name
  description = "GCE instance name (always devops-instance)."
}

output "vm_instance_zone" {
  value       = module.gcp_infra.instance_zone
  description = "GCE zone where the instance was created."
}

output "ssh_command" {
  value       = "gcloud compute ssh isahjohna@devops-instance --zone=${var.gcp_zone} --project=${var.gcp_project_id}"
  description = "Ready-to-run gcloud command to SSH into devops-instance."
}

output "ssh_command_short" {
  value       = <<-EOT
    # One-time: set gcloud defaults so you never need flags again
    gcloud config set project ${var.gcp_project_id}
    gcloud config set compute/zone ${var.gcp_zone}

    # Then connect any time with just:
    gcloud compute ssh isahjohna@devops-instance
  EOT
  description = "How to set gcloud defaults so the SSH command needs no flags."
}

# ── Stage 2 outputs ──────────────────────────────────────────────────────────────

output "dns_records" {
  value       = module.cloudflare_dns.hostnames
  description = "All DNS hostnames created in Cloudflare."
}

output "cluster_init_id" {
  value       = module.cluster_init.complete
  description = "Populated once cluster_init has run. Confirms Minikube and NGINX are up."
}

# ── Stage 3 outputs ──────────────────────────────────────────────────────────────

output "argocd_url" {
  value       = module.cluster_bootstrap.argocd_url
  description = "ArgoCD web UI URL."
}

output "argocd_admin_password_command" {
  value       = "gcloud compute ssh isahjohna@devops-instance -- kubectl -n argocd get secret argocd-deploy-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode && echo"
  description = "Command to retrieve the ArgoCD initial admin password."
}
