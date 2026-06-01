variable "vm_ip" {
  type        = string
  description = "Static external IP of devops-instance."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Absolute path to the SSH private key for the isahjohna user."
}

variable "argocd_project_yaml_path" {
  type        = string
  description = "Local path to k8s/argocd/project.yaml."
}

variable "argocd_root_app_yaml_path" {
  type        = string
  description = "Local path to k8s/argocd/root-app.yaml (App of Apps bootstrap)."
}
