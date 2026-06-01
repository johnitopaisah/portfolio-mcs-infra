resource "null_resource" "cluster_bootstrap" {
  triggers = {
    vm_ip                = var.vm_ip
    cert_manager_version = var.cert_manager_version
    argocd_domain        = var.argocd_domain
  }

  connection {
    type        = "ssh"
    user        = "isahjohna"
    host        = var.vm_ip
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # ── Upload YAML files ─────────────────────────────────────────────────────
  provisioner "file" {
    source      = var.cluster_issuer_yaml_path
    destination = "/tmp/cluster-issuer.yaml"
  }

  provisioner "file" {
    source      = var.argocd_values_yaml_path
    destination = "/tmp/argocd-values.yaml"
  }

  provisioner "file" {
    source      = var.argocd_ingress_yaml_path
    destination = "/tmp/argocd-ingress-traefik.yaml"
  }

  provisioner "file" {
    source      = var.infisical_secret_ecommerce_yaml_path
    destination = "/tmp/infisical-secret-ecommerce.yaml"
  }

  provisioner "file" {
    source      = var.infisical_secret_portfolio_yaml_path
    destination = "/tmp/infisical-secret-porfolio.yaml"
  }

  # ── Upload bootstrap script ───────────────────────────────────────────────
  provisioner "file" {
    source      = "${path.module}/scripts/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  # ── Write sensitive credentials to a temp env file ────────────────────────
  # Credentials are written to a file rather than passed inline so they never
  # appear in the executed command string. bootstrap.sh sources this file and
  # deletes it on completion.
  provisioner "file" {
    content     = <<-ENV
      export INFISICAL_ECOMMERCE_CLIENT_ID='${var.infisical_ecommerce_client_id}'
      export INFISICAL_ECOMMERCE_CLIENT_SECRET='${var.infisical_ecommerce_client_secret}'
      export INFISICAL_PORTFOLIO_CLIENT_ID='${var.infisical_portfolio_client_id}'
      export INFISICAL_PORTFOLIO_CLIENT_SECRET='${var.infisical_portfolio_client_secret}'
    ENV
    destination = "/tmp/.bootstrap_env"
  }

  # ── Run bootstrap script ──────────────────────────────────────────────────
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "chmod 600 /tmp/.bootstrap_env",
      "CERT_MANAGER_VERSION='${var.cert_manager_version}' ARGOCD_DOMAIN='${var.argocd_domain}' bash /tmp/bootstrap.sh",
    ]
  }
}
