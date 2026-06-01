resource "null_resource" "cluster_init" {
  # Re-run if the VM is replaced (IP changes) or any version pin changes.
  triggers = {
    vm_ip            = var.vm_ip
    minikube_version = var.minikube_version
    k8s_version      = var.k8s_version
    helm_version     = var.helm_version
  }

  connection {
    type        = "ssh"
    user        = "isahjohna"
    host        = var.vm_ip
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # Upload nginx.conf from bootstrapping/ — init.sh patches the Minikube IP.
  provisioner "file" {
    source      = var.nginx_conf_path
    destination = "/tmp/nginx.conf"
  }

  # Upload the init script.
  provisioner "file" {
    source      = "${path.module}/scripts/init.sh"
    destination = "/tmp/init.sh"
  }

  # ── Block 1: install Docker and add user to docker group ─────────────────────
  # This is a separate SSH connection. It must complete and disconnect before
  # Block 2 connects, so that the new session picks up the docker group.
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io conntrack socat curl apt-transport-https ca-certificates gnupg lsb-release libnginx-mod-stream",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker isahjohna",
      "echo 'Docker installed and isahjohna added to docker group.'",
    ]
  }

  # ── Block 2: new SSH connection — docker group is now active ─────────────────
  # Each remote-exec block opens a fresh SSH session. This new login picks up
  # the docker group from /etc/group, so minikube (and all subsequent commands
  # that talk to the Docker socket) work without sg docker or newgrp.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/init.sh",
      "MINIKUBE_VERSION='${var.minikube_version}' K8S_VERSION='${var.k8s_version}' HELM_VERSION='${var.helm_version}' bash /tmp/init.sh",
    ]
  }
}
