locals {
  # Path where cluster_init writes the patched kubeconfig after Minikube starts.
  # The .kube/ directory is gitignored. This path is consumed by the kubernetes
  # and helm providers and by modules that reference the cluster.
  kubeconfig_path = "${path.module}/.kube/devops-minikube.yaml"

  # Labels applied to every GCP resource created by this configuration.
  common_labels = {
    project    = "portfolio-mcs"
    managed-by = "terraform"
  }
}
