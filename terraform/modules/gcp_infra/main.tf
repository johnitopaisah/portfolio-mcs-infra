# ── Ubuntu 25.10 image ───────────────────────────────────────────────────────────
# Look up the latest Ubuntu 25.10 image from the GCP-managed ubuntu-os-cloud project.
# Using a data source (instead of a hardcoded image ID) ensures we always get the
# current patched image within the 25.10 family on each fresh deployment.
data "google_compute_image" "ubuntu_2510" {
  # GCP appends the architecture suffix for non-LTS Ubuntu releases.
  # LTS releases use e.g. "ubuntu-2404-lts"; interim releases use "ubuntu-YYMM-amd64".
  family  = "ubuntu-2510-amd64"
  project = "ubuntu-os-cloud"
}

# ── Static external IP ───────────────────────────────────────────────────────────
# Reserved before instance creation so Cloudflare DNS records always have a stable
# target. VM recreates never change this address.
resource "google_compute_address" "static_ip" {
  name   = "devops-instance-ip"
  region = var.region
}

# ── VPC network ──────────────────────────────────────────────────────────────────
# Custom-mode VPC — no automatic subnets created. We control exactly what exists.
resource "google_compute_network" "vpc" {
  name                    = "portfolio-mcs-vpc"
  auto_create_subnetworks = false
}

# ── Subnet ───────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = "portfolio-mcs-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# ── Firewall: SSH ────────────────────────────────────────────────────────────────
# Restrict to ssh_source_ranges — set to your own IP in terraform.tfvars.
resource "google_compute_firewall" "allow_ssh" {
  name    = "portfolio-mcs-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["devops-instance"]
}

# ── Firewall: HTTP / HTTPS ───────────────────────────────────────────────────────
# Required for: Cloudflare proxy (ports 80, 443), Let's Encrypt ACME HTTP-01 challenges.
resource "google_compute_firewall" "allow_http_https" {
  name    = "portfolio-mcs-allow-http-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["devops-instance"]
}

# ── Firewall: NodePorts ──────────────────────────────────────────────────────────
# Traefik is exposed via Minikube NodePorts 30080 (HTTP) and 30443 (HTTPS).
# NGINX on the host proxies external traffic to these ports.
# The full NodePort range is open to allow flexibility; restrict if needed.
resource "google_compute_firewall" "allow_nodeports" {
  name    = "portfolio-mcs-allow-nodeports"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["devops-instance"]
}

# ── VM service account ───────────────────────────────────────────────────────────
# Separate from the Terraform SA. Attached to the instance for any GCP API calls
# the VM itself needs to make (e.g. pulling images from Artifact Registry later).
# Scoped to cloud-platform on the instance but no project-level IAM roles granted
# here — add them explicitly when a specific GCP service is needed from the VM.
resource "google_service_account" "vm_sa" {
  account_id   = "devops-instance-sa"
  display_name = "DevOps Instance Service Account"
  project      = var.project
}

# ── GCE instance ─────────────────────────────────────────────────────────────────
resource "google_compute_instance" "devops_instance" {
  name         = "devops-instance"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["devops-instance"]
  labels       = var.common_labels

  boot_disk {
    initialize_params {
      # pd-ssd gives noticeably faster Minikube node start times vs pd-standard.
      image = data.google_compute_image.ubuntu_2510.self_link
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {
      # Bind the pre-reserved static IP to this instance.
      nat_ip = google_compute_address.static_ip.address
    }
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  # Two SSH access methods coexist here:
  #
  # 1. Custom key (ssh-keys metadata) — used by Terraform remote-exec provisioner.
  #    Key path comes from var.ssh_public_key_path in terraform.tfvars.
  #
  # 2. gcloud compute ssh — uses gcloud's own managed key (~/.ssh/google_compute_engine).
  #    gcloud injects its key at the GCP PROJECT level automatically on first use.
  #    block-project-ssh-keys is explicitly false so project-level keys are always allowed.
  #    This lets you run: gcloud compute ssh isahjohna@devops-instance
  metadata = {
    ssh-keys               = "isahjohna:${file(var.ssh_public_key_path)}"
    block-project-ssh-keys = "false"
  }

  # Grant isahjohna passwordless sudo.
  # The guest agent creates the user from metadata; this startup script adds the
  # sudoers entry. Both run on first boot — the || true handles race conditions
  # if the user already exists by the time this script runs.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    useradd -m -s /bin/bash isahjohna 2>/dev/null || true
    usermod -aG sudo isahjohna
    echo 'isahjohna ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/100-isahjohna
    chmod 0440 /etc/sudoers.d/100-isahjohna
  EOT

  # Prevent accidental recreation of the instance on metadata changes after
  # initial provisioning. Remove this lifecycle block if you intentionally
  # need to replace the instance (e.g. machine type change).
  lifecycle {
    ignore_changes = [
      metadata_startup_script,
    ]
  }
}
