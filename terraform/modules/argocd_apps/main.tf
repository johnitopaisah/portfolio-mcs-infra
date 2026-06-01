resource "null_resource" "argocd_apps" {
  triggers = {
    vm_ip = var.vm_ip
  }

  connection {
    type        = "ssh"
    user        = "isahjohna"
    host        = var.vm_ip
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # Upload ArgoCD project definition.
  provisioner "file" {
    source      = var.argocd_project_yaml_path
    destination = "/tmp/argocd-project.yaml"
  }

  # Upload the root App of Apps.
  # This single Application points ArgoCD at k8s/argocd/ in the Git repo.
  # ArgoCD then discovers and reconciles all child Applications automatically.
  provisioner "file" {
    source      = var.argocd_root_app_yaml_path
    destination = "/tmp/argocd-root-app.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "kubectl config use-context devops-minikube",

      # Create the AppProject first (sync-wave -1 ensures it precedes child apps).
      "kubectl apply -f /tmp/argocd-project.yaml -n argocd",

      # Seed the root Application. ArgoCD syncs k8s/argocd/ and discovers
      # all child apps (api, user-ui, admin-ui, monitoring, etc.) automatically.
      "kubectl apply -f /tmp/argocd-root-app.yaml -n argocd",

      # Brief pause so ArgoCD can register the application.
      "sleep 10",

      # Print status — not a hard wait since sync takes time and depends on
      # ArgoCD being able to reach the Git repo.
      "kubectl get application portfolio-root -n argocd 2>/dev/null || echo 'App registered — ArgoCD is syncing'",
      "echo 'ArgoCD App of Apps seeded. Monitor sync at https://argocd-deploy.johnisah.org'",
    ]
  }
}
