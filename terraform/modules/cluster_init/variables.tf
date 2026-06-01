variable "vm_ip" {
  type        = string
  description = "Static external IP of devops-instance. Used as the SSH target."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Absolute path to the SSH private key for the isahjohna user."
}

variable "minikube_version" {
  type        = string
  description = "Minikube release version to install (e.g. v1.38.1)."
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version for the Minikube cluster (e.g. v1.34.2)."
}

variable "helm_version" {
  type        = string
  description = "Helm v3 CLI version to install (e.g. v3.21.0)."
}

variable "nginx_conf_path" {
  type        = string
  description = "Absolute local path to bootstrapping/nginx.conf. Uploaded to the VM and patched with the real Minikube IP."
}
