# Terraform — Portfolio MCS Infrastructure

This directory contains all Terraform configuration to provision and bootstrap the Portfolio MCS platform on GCP. It implements a three-stage deployment pipeline that produces a fully operational GitOps-driven Kubernetes cluster running on a single GCE instance, with automated DNS, TLS, secrets management, and continuous delivery via ArgoCD.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Directory Structure](#3-directory-structure)
4. [Quick Start](#4-quick-start)
5. [Root Configuration Files](#5-root-configuration-files)
6. [Modules](#6-modules)
   - [gcp\_infra](#61-module-gcp_infra)
   - [cloudflare\_dns](#62-module-cloudflare_dns)
   - [cluster\_init](#63-module-cluster_init)
   - [cluster\_bootstrap](#64-module-cluster_bootstrap)
   - [argocd\_apps](#65-module-argocd_apps)
7. [Helper Scripts](#7-helper-scripts)
8. [Variables Reference](#8-variables-reference)
9. [Outputs Reference](#9-outputs-reference)
10. [Deployment Stages](#10-deployment-stages)
11. [Networking & Traffic Flow](#11-networking--traffic-flow)
12. [Secret Management](#12-secret-management)
13. [DNS Records](#13-dns-records)
14. [Design Decisions](#14-design-decisions)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Architecture Overview

```
External Traffic
      │
      ▼
Cloudflare DNS (johnisah.org)
      │  proxied / DNS-only
      ▼
GCE Instance (e2-standard-4, Ubuntu 25.10, 100GB pd-ssd)
  Static IP: 34.65.x.x  ──── GCP VPC: 10.0.1.0/24
      │
    NGINX (host-level reverse proxy)
      │  :80/:443  →  :30080/:30443
      ▼
  Minikube Cluster (2-node, containerd, v1.34.2)
    ├── Traefik (IngressController, NodePort 30080/30443)
    ├── cert-manager (v1.20.2, Let's Encrypt HTTP-01)
    ├── Infisical Secrets Operator
    ├── ArgoCD  →  pulls from GitHub (develop branch)
    │     └── App of Apps  →  syncs k8s/argocd/*
    └── Workloads: api, admin-ui, user-ui, shopnow, grafana, prometheus
```

Terraform drives provisioning in three ordered stages. After Stage 3, ArgoCD owns all workload reconciliation and Terraform is no longer involved in day-to-day operations.

---

## 2. Prerequisites

### Required Tools

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Terraform | ≥ 1.6.0 | https://developer.hashicorp.com/terraform/install |
| gcloud CLI | any | https://cloud.google.com/sdk/docs/install |

Run the pre-flight check to validate both:

```bash
./terraform/scripts/check-tools.sh
```

### Required Accounts & Access

| System | What You Need |
|--------|--------------|
| GCP | Project owner or equivalent IAM role |
| Cloudflare | API token with DNS:Edit permission on the `johnisah.org` zone |
| Infisical | Machine identity credentials for `ecommerce` and `portfolio` namespaces |
| GitHub | Read access to this repository (used by ArgoCD) |

### Required Local Files (outside the repo)

| File | Purpose |
|------|---------|
| `~/.gcp/portfolio-mcs-terraform-sa-key.json` | Terraform GCP service account key |
| `~/.ssh/ssh-key-2026-03-23.key` | SSH private key (injected into VM) |
| `~/.ssh/ssh-key-2026-03-23.key.pub` | SSH public key |

Run the one-shot GCP setup if the service account and GCS state bucket do not yet exist:

```bash
./terraform/scripts/setup-gcp-prereqs.sh portfolio-mcs-prod europe-west9 europe-west9-a
```

### Environment Variable

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp/portfolio-mcs-terraform-sa-key.json
```

This must be set before any `terraform` command. The remote state backend reads it at init time.

---

## 3. Directory Structure

```
terraform/
├── backend.tf                  # GCS remote state (bucket: portfolio-mcs-prod-tfstate)
├── versions.tf                 # Terraform ≥1.6 + provider version locks
├── providers.tf                # google, cloudflare, kubernetes, helm provider config
├── variables.tf                # All 27 root input variables
├── locals.tf                   # kubeconfig_path, common_labels
├── main.tf                     # Orchestrates 5 modules across 3 stages
├── outputs.tf                  # vm_static_ip, ssh_command, dns_records, argocd_url, …
├── terraform.tfvars            # Actual values (gitignored)
├── terraform.tfvars.example    # Template — copy and fill in
│
├── modules/
│   ├── gcp_infra/              # Stage 1: GCP resources
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── cloudflare_dns/         # Stage 2a: 8 DNS records
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   ├── cluster_init/           # Stage 2b: Docker + Minikube + NGINX on VM
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── scripts/
│   │       └── init.sh
│   │
│   ├── cluster_bootstrap/      # Stage 3a: Traefik, cert-manager, Infisical, ArgoCD
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── scripts/
│   │       └── bootstrap.sh
│   │
│   └── argocd_apps/            # Stage 3b: ArgoCD AppProject + root Application
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── scripts/                    # Local helper scripts (run on workstation)
    ├── check-tools.sh          # Pre-flight: validates terraform + gcloud
    ├── setup-gcp-prereqs.sh    # One-shot GCP project + SA + GCS bucket creation
    └── decode-infisical-creds.sh # Decodes base64 creds → terraform.tfvars snippet
```

---

## 4. Quick Start

```bash
# 0. Clone and enter the repo
cd portfolio-mcs

# 1. Validate prerequisites
./terraform/scripts/check-tools.sh

# 2. Copy and fill in variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your actual values

# 3. Set GCP credentials
export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp/portfolio-mcs-terraform-sa-key.json

# 4. Initialize Terraform
cd terraform
terraform init

# 5. Stage 1 — GCP Infrastructure
terraform apply -target=module.gcp_infra

# 6. Stage 2 — DNS + Cluster Init (parallel)
terraform apply -target=module.cloudflare_dns -target=module.cluster_init

# 7. Verify cluster
kubectl --kubeconfig=../.kube/devops-minikube.yaml get nodes

# 8. Stage 3 — Full Bootstrap
terraform apply

# 9. Get ArgoCD initial admin password
kubectl --kubeconfig=../.kube/devops-minikube.yaml \
  -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

ArgoCD is now live at `https://argocd-deploy.johnisah.org`. It will automatically discover and sync all child applications from `k8s/argocd/` on the `develop` branch.

---

## 5. Root Configuration Files

### `versions.tf`

Declares the minimum Terraform version and pins all provider versions:

| Provider | Version Constraint |
|----------|--------------------|
| `hashicorp/google` | `~5.0` |
| `cloudflare/cloudflare` | `~4.0` |
| `hashicorp/kubernetes` | `~2.0` |
| `hashicorp/helm` | `~2.0` |
| `hashicorp/null` | `~3.0` |
| `hashicorp/local` | `~2.0` |

### `providers.tf`

- **google**: Authenticates using the path from `var.gcp_credentials_file`, targets `var.gcp_project_id`, `var.gcp_region`, and `var.gcp_zone`.
- **cloudflare**: Authenticated via `var.cloudflare_api_token`.
- **kubernetes**: Connects to the Minikube cluster using the kubeconfig written by `cluster_init` (`local.kubeconfig_path` → `.kube/devops-minikube.yaml`).
- **helm**: Uses the same kubeconfig as the Kubernetes provider.

### `backend.tf`

Remote state is stored in GCS:

```
bucket  = "portfolio-mcs-prod-tfstate"
prefix  = "portfolio-mcs/state"
```

Credentials are loaded from `GOOGLE_APPLICATION_CREDENTIALS`. The Terraform service account must have `roles/storage.objectAdmin` on this bucket.

### `locals.tf`

| Local | Value | Usage |
|-------|-------|-------|
| `kubeconfig_path` | `.kube/devops-minikube.yaml` | Provider auth, kubectl commands |
| `common_labels` | `{project: portfolio-mcs, managed-by: terraform}` | Applied to all GCP resources |

### `main.tf`

Orchestrates all five modules and encodes the three-stage dependency chain:

```
gcp_infra
    ├── cloudflare_dns   (depends_on: gcp_infra)
    ├── cluster_init     (depends_on: gcp_infra)
    └── cluster_bootstrap (depends_on: cluster_init)
            └── argocd_apps (depends_on: cluster_bootstrap)
```

`cloudflare_dns` and `cluster_init` have no dependency on each other and run in parallel during Stage 2.

---

## 6. Modules

### 6.1 Module: `gcp_infra`

**Purpose**: Provisions all GCP resources required to host the cluster.

**Resources created:**

| Resource | Name | Notes |
|----------|------|-------|
| `google_compute_address` | `devops-instance-ip` | Static external IP; stable across VM recreations |
| `google_compute_network` | `portfolio-mcs-vpc` | Custom-mode VPC, no auto-subnets |
| `google_compute_subnetwork` | `portfolio-mcs-subnet` | CIDR: 10.0.1.0/24 |
| `google_compute_firewall` | SSH rule | Port 22; restricted to `ssh_source_ranges` |
| `google_compute_firewall` | HTTP/HTTPS rule | Ports 80, 443; open to 0.0.0.0/0 |
| `google_compute_firewall` | NodePort rule | Ports 30000–32767; open to 0.0.0.0/0 |
| `google_service_account` | `devops-instance-sa` | VM identity with cloud-platform scope |
| `google_compute_instance` | `devops-instance` | e2-standard-4, 100GB pd-ssd, Ubuntu 25.10 |

**VM details:**
- Machine type: `e2-standard-4` (4 vCPU, 16GB RAM)
- Boot disk: 100GB `pd-ssd`
- Image: Latest Ubuntu 25.10 from `ubuntu-os-cloud`
- Network: Attached to `portfolio-mcs-subnet` with the reserved static IP
- SSH: `isahjohna` user injected via instance metadata; `block-project-ssh-keys: false` allows gcloud-managed keys
- Startup script: Creates `isahjohna` user, adds to `docker` group, grants passwordless `sudo`
- Lifecycle: Ignores `metadata_startup_script` changes after initial creation

**Key outputs:**

| Output | Description |
|--------|-------------|
| `static_ip` | Static external IP — used by all downstream modules |
| `instance_name` | Always `devops-instance` |
| `instance_zone` | Zone where instance was created |
| `vm_sa_email` | Email of VM service account |

---

### 6.2 Module: `cloudflare_dns`

**Purpose**: Creates 8 DNS records for `johnisah.org` pointing to the static IP.

**DNS records:**

| Subdomain | Type | Proxied | TTL | Notes |
|-----------|------|---------|-----|-------|
| `@` (root) | A | Yes | auto | Main site |
| `www` | CNAME → `johnisah.org` | Yes | auto | |
| `api` | A | Yes | auto | Backend API |
| `admin` | A | Yes | auto | Admin UI |
| `shopnow` | A | Yes | auto | Ecommerce storefront |
| `argocd-deploy` | A | No | 300s | WebSockets break via Cloudflare proxy |
| `grafana` | A | No | 300s | WebSocket live updates |
| `prom-dashboard` | A | No | 300s | Internal tooling |

Proxied records benefit from Cloudflare CDN and DDoS protection. DNS-only records are used wherever Cloudflare's proxy would interfere with WebSocket connections.

**Key outputs:**

| Output | Description |
|--------|-------------|
| `hostnames` | Map of all 8 DNS record hostnames |

---

### 6.3 Module: `cluster_init`

**Purpose**: SSHes into the GCE instance and installs all cluster tooling, then starts a two-node Minikube cluster and configures NGINX as a host-level reverse proxy.

**Execution model**: `null_resource` with SSH file + remote-exec provisioners. Re-runs when the VM IP or any pinned tool version changes.

**What `init.sh` does (idempotent):**

1. Install **Minikube** (`v1.38.1`) if not already present
2. Install **kubectl** (`v1.34.2`) if not already present
3. Install **Helm v3** (`v3.21.0`) if not already present
4. Add Helm repositories: `argo`, `cert-manager`, `infisical-helm-charts`, `traefik`
5. Start Minikube:
   - Profile: `devops-minikube`
   - Driver: `docker`
   - Container runtime: `containerd`
   - 2 nodes, 2 CPUs each, 4096MB RAM each, 20GB disk each
   - `--embed-certs=true` (kubeconfig works without separate CA file)
6. Enable addons: `metrics-server`, `default-storageclass`, `storage-provisioner`
7. Wait up to 5 minutes for all nodes to reach `Ready` state
8. Install and configure **NGINX**:
   - Remove Ubuntu default site
   - Copy `bootstrapping/nginx.conf` to `/etc/nginx/nginx.conf`
   - Patch config with the live Minikube IP (dynamically read via `minikube ip -p devops-minikube`)
   - Test, enable, and restart NGINX
9. Logs to `/tmp/init.log`

**Two-phase SSH connection**: Docker is installed in Phase 1. Phase 2 opens a fresh SSH session to pick up the new `docker` group membership from `/etc/group` before running Minikube (which requires the `docker` socket).

**Writes kubeconfig** to `.kube/devops-minikube.yaml` on the local workstation (used by the Kubernetes and Helm providers in Stage 3).

**Key outputs:**

| Output | Description |
|--------|-------------|
| `complete` | Non-null once provisioning finishes; used as `depends_on` by `cluster_bootstrap` |

---

### 6.4 Module: `cluster_bootstrap`

**Purpose**: Installs all cluster-level platform components via SSH in strict dependency order.

**Execution model**: `null_resource` with SSH file + remote-exec provisioners. Re-runs when VM IP, cert-manager version, or ArgoCD domain changes.

**Files uploaded to VM before execution:**

| Local Path | Uploaded To |
|-----------|-------------|
| `bootstrapping/cluster-issuer.yaml` | `/tmp/cluster-issuer.yaml` |
| `bootstrapping/argocd-values.yaml` | `/tmp/argocd-values.yaml` |
| `bootstrapping/argocd-ingress-traefik.yaml` | `/tmp/argocd-ingress-traefik.yaml` |
| `bootstrapping/infisical-secret-ecommerce.yaml` | `/tmp/infisical-secret-ecommerce.yaml` |
| `bootstrapping/infisical-secret-porfolio.yaml` | `/tmp/infisical-secret-porfolio.yaml` |
| Sensitive credentials | `/tmp/.bootstrap_env` (deleted at script end) |

**What `bootstrap.sh` does (idempotent, in order):**

1. **Refresh Helm index** — ensures all repos added in `init.sh` are current
2. **Create 7 namespaces**: `traefik`, `argocd`, `cert-manager`, `infisical`, `ecommerce`, `portfolio`, `monitoring`
3. **Install Traefik** (Helm, `traefik/traefik`):
   - Service type: `NodePort`
   - HTTP NodePort: `30080`, HTTPS NodePort: `30443`
   - Wait 300s for rollout
4. **Install cert-manager** (Helm, `cert-manager/cert-manager`, `v1.20.2`):
   - `--set installCRDs=true`
   - Wait 300s, verify 3 deployments ready
5. **Create Let's Encrypt ClusterIssuer**:
   - Apply `cluster-issuer.yaml`
   - Wait for `letsencrypt-prod` condition `Ready`
6. **Install Infisical secrets operator** (Helm, `infisical-helm-charts/secrets-operator`):
   - `--set installCRDs=true`
   - Wait 300s, verify deployment available
7. **Create Kubernetes Secrets** with Infisical machine identity credentials:
   - `infisical-machine-identity` in `ecommerce` namespace
   - `infisical-machine-identity` in `portfolio` namespace
8. **Apply InfisicalSecret CRs** — operator fetches actual application secrets from Infisical SaaS
9. **Install ArgoCD** (Helm, `argo/argo-cd`, release name `argocd-deploy`):
   - Global domain: `argocd-deploy.johnisah.org`
   - Custom values from `argocd-values.yaml`
   - Wait 600s, verify 6 deployments + 1 statefulset ready
10. **Apply ArgoCD Traefik ingress** (`argocd-ingress-traefik.yaml`)
11. **Cleanup**: Delete `/tmp/.bootstrap_env`

Logs to `/tmp/bootstrap.log`.

**Key outputs:**

| Output | Description |
|--------|-------------|
| `complete` | Non-null once bootstrap finishes |
| `argocd_url` | `https://argocd-deploy.johnisah.org` |

---

### 6.5 Module: `argocd_apps`

**Purpose**: Seeds the ArgoCD App of Apps pattern by applying an `AppProject` and a root `Application` CR. ArgoCD then discovers and reconciles all child applications automatically.

**Execution model**: `null_resource` with SSH provisioners. Re-runs when the VM IP changes.

**Files uploaded and applied:**

| File | ArgoCD Resource | Purpose |
|------|----------------|---------|
| `k8s/argocd/project.yaml` | `AppProject` | Defines allowed source repos, destinations, and sync policies |
| `k8s/argocd/root-app.yaml` | `Application` | Root app pointing to `k8s/argocd/` in the repo |

**Sync order**: `AppProject` is applied first (sync-wave `-1` ensures it precedes child apps). The root `Application` is applied second; ArgoCD then crawls `k8s/argocd/` on the `develop` branch and creates all child `Application` objects.

**Key outputs:**

| Output | Description |
|--------|-------------|
| `complete` | Non-null once ArgoCD Application CRs are applied |

---

## 7. Helper Scripts

All scripts live in `terraform/scripts/` and are run on the local workstation (not on the VM).

### `check-tools.sh`

Pre-flight validation before `terraform init`. Checks:
- Terraform is installed and version ≥ 1.6
- gcloud CLI is installed
- gcloud has an active authenticated account
- gcloud has a default project configured
- `GOOGLE_APPLICATION_CREDENTIALS` is set and the key file exists

Exits with code `1` if any check fails. Run this before every fresh `terraform init`.

```bash
./terraform/scripts/check-tools.sh
```

### `setup-gcp-prereqs.sh`

One-shot bootstrap of GCP project prerequisites. All steps are idempotent. Run once per new environment.

```bash
./terraform/scripts/setup-gcp-prereqs.sh <PROJECT_ID> [REGION] [ZONE]
# Example:
./terraform/scripts/setup-gcp-prereqs.sh portfolio-mcs-prod europe-west9 europe-west9-a
```

What it does:
1. Verifies gcloud authentication
2. Creates the GCP project if it does not exist
3. Prints a reminder to enable billing in the browser
4. Enables required APIs: `compute`, `storage`, `iam`, `cloudresourcemanager`
5. Creates the `terraform-sa` service account
6. Grants IAM roles: `roles/compute.admin`, `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser`, `roles/storage.admin`
7. Creates the GCS state bucket with versioning enabled
8. Grants `roles/storage.objectAdmin` on the bucket to the service account
9. Downloads the service account key to `~/.gcp/`
10. Patches `terraform/backend.tf` with the real bucket name
11. Prints the `gcp_*` block to paste into `terraform.tfvars`

### `decode-infisical-creds.sh`

Decodes base64-encoded Infisical machine identity credentials from `bootstrapping/infisical-auth-secret-*.yaml` files and prints them as a `terraform.tfvars`-ready snippet. Useful when Infisical credentials are stored as Kubernetes Secret manifests.

```bash
./terraform/scripts/decode-infisical-creds.sh
```

---

## 8. Variables Reference

### GCP Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `gcp_project_id` | — | GCP project ID |
| `gcp_region` | `europe-west9` | GCP region for all resources |
| `gcp_zone` | `europe-west9-a` | GCP zone for the GCE instance |
| `gcp_credentials_file` | — | Path to Terraform SA key file (must be outside repo) |
| `machine_type` | `e2-standard-4` | GCE machine type |
| `disk_size_gb` | `100` | Boot disk size in GB |
| `ssh_source_ranges` | `128.78.214.46/32` | CIDR ranges allowed to SSH to the VM |

### SSH Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_public_key_path` | — | Path to SSH public key (injected as `isahjohna` user on VM) |
| `ssh_private_key_path` | — | Path to SSH private key (used by Terraform provisioners) |

### Cloudflare Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cloudflare_api_token` | — | API token with DNS:Edit on johnisah.org zone; marked sensitive |
| `cloudflare_zone_id` | — | Zone ID for johnisah.org |

### Infisical Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `infisical_ecommerce_client_id` | — | Machine identity client ID for ecommerce namespace; sensitive |
| `infisical_ecommerce_client_secret` | — | Machine identity client secret for ecommerce namespace; sensitive |
| `infisical_portfolio_client_id` | — | Machine identity client ID for portfolio namespace; sensitive |
| `infisical_portfolio_client_secret` | — | Machine identity client secret for portfolio namespace; sensitive |

### ArgoCD Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `argocd_repo_url` | — | HTTPS clone URL of this repository |
| `argocd_target_revision` | `develop` | Git branch or tag ArgoCD tracks for manifest sync |

### Tool Version Variables (pinned)

| Variable | Pinned Value | Notes |
|----------|-------------|-------|
| `minikube_version` | `v1.38.1` | |
| `k8s_version` | `v1.34.2` | Tested with this ArgoCD configuration |
| `helm_version` | `v3.21.0` | Helm v3.x — do NOT use v4 |
| `cert_manager_version` | `v1.20.2` | |

---

## 9. Outputs Reference

| Output | Description |
|--------|-------------|
| `vm_static_ip` | Static external IP of `devops-instance` |
| `vm_instance_name` | GCE instance name (`devops-instance`) |
| `vm_instance_zone` | Zone where instance was created |
| `ssh_command` | Ready-to-run `gcloud compute ssh` command |
| `ssh_command_short` | Instructions for setting gcloud defaults then using short form |
| `dns_records` | Map of all 8 DNS hostnames created in Cloudflare |
| `cluster_init_id` | Non-null value confirming Minikube and NGINX are up |
| `argocd_url` | `https://argocd-deploy.johnisah.org` |
| `argocd_admin_password_command` | `kubectl` command to retrieve the initial ArgoCD admin password |

---

## 10. Deployment Stages

### Stage 1 — GCP Infrastructure

```bash
terraform apply -target=module.gcp_infra
```

Creates all GCP resources. Note the `vm_static_ip` output — it is passed to every subsequent module.

**Verify**: SSH into the instance before proceeding.

```bash
gcloud compute ssh isahjohna@devops-instance --project=portfolio-mcs-prod --zone=europe-west9-a
```

### Stage 2 — Cloudflare DNS + Cluster Initialization

```bash
terraform apply -target=module.cloudflare_dns -target=module.cluster_init
```

Both modules depend on `gcp_infra` and run in parallel:

- `cloudflare_dns` creates 8 DNS records pointing to the static IP
- `cluster_init` SSHes into the VM and installs Docker, Minikube, kubectl, Helm, and NGINX

This stage takes 10–15 minutes while Minikube boots and the init script runs.

**Verify DNS:**
```bash
dig +short johnisah.org
dig +short argocd-deploy.johnisah.org
```

**Verify cluster:**
```bash
kubectl --kubeconfig=.kube/devops-minikube.yaml get nodes
```

### Stage 3 — Full Bootstrap

```bash
terraform apply
```

Runs the two remaining modules sequentially:

1. `cluster_bootstrap` installs Traefik, cert-manager, Infisical operator, and ArgoCD (takes 15–20 minutes)
2. `argocd_apps` applies the AppProject and root Application; ArgoCD takes over from here

**Verify ArgoCD:**
```bash
# Get admin password
kubectl --kubeconfig=.kube/devops-minikube.yaml \
  -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open UI
open https://argocd-deploy.johnisah.org
```

### Dependency Graph

```
module.gcp_infra
    ├── module.cloudflare_dns   ← parallel
    ├── module.cluster_init     ← parallel
    │       └── module.cluster_bootstrap
    │                   └── module.argocd_apps
```

---

## 11. Networking & Traffic Flow

```
Internet
  │
  ▼
Cloudflare (johnisah.org DNS)
  │  Proxied records: CDN + DDoS protection
  │  DNS-only records: direct passthrough (WebSocket safe)
  ▼
GCE Static IP (port 80 / 443)
  │  Firewall: HTTP/HTTPS open to 0.0.0.0/0
  ▼
NGINX on VM host (listening on :80 and :443)
  │  Reverse-proxies to Minikube NodePorts
  ▼
Traefik (NodePort :30080 / :30443 on Minikube)
  │  Firewall: NodePort range 30000–32767 open to 0.0.0.0/0
  ▼
In-cluster Services (api, admin-ui, user-ui, shopnow, …)
```

**TLS**: cert-manager issues Let's Encrypt certificates via HTTP-01 challenges. The challenge request travels: Let's Encrypt → Cloudflare → NGINX → Traefik → cert-manager solver pod.

**SSH access**: Port 22 is restricted to the CIDR in `ssh_source_ranges` (default: a single /32).

---

## 12. Secret Management

All sensitive values flow through multiple layers without ever being committed to Git or appearing in Terraform state in plaintext.

| Secret | Where Stored | How Used |
|--------|-------------|----------|
| Cloudflare API token | `terraform.tfvars` (gitignored), `sensitive = true` | Provider auth at plan/apply time |
| Infisical machine identity credentials | `terraform.tfvars` (gitignored), `sensitive = true` | Written to `/tmp/.bootstrap_env`, sourced by `bootstrap.sh`, deleted after use |
| GCP service account key | `~/.gcp/` (outside repo) | `GOOGLE_APPLICATION_CREDENTIALS` env var |
| SSH private key | `~/.ssh/` (outside repo) | Terraform SSH provisioner connections |
| Application secrets (DB passwords, API keys, etc.) | Infisical SaaS | Infisical operator syncs them into Kubernetes Secrets at runtime |
| ArgoCD initial admin password | Kubernetes Secret in `argocd` namespace | Retrieved with `kubectl get secret argocd-initial-admin-secret` |

The `terraform.tfvars` file is gitignored. Copy `terraform.tfvars.example`, fill in values, and never commit the result.

---

## 13. DNS Records

All records are in the `johnisah.org` Cloudflare zone.

| Hostname | Type | Value | Proxied | Purpose |
|----------|------|-------|---------|---------|
| `johnisah.org` | A | `<static_ip>` | Yes | Portfolio root |
| `www.johnisah.org` | CNAME | `johnisah.org` | Yes | www redirect |
| `api.johnisah.org` | A | `<static_ip>` | Yes | Backend API |
| `admin.johnisah.org` | A | `<static_ip>` | Yes | Admin dashboard |
| `shopnow.johnisah.org` | A | `<static_ip>` | Yes | Ecommerce store |
| `argocd-deploy.johnisah.org` | A | `<static_ip>` | No | ArgoCD UI (WebSocket) |
| `grafana.johnisah.org` | A | `<static_ip>` | No | Grafana dashboards (WebSocket) |
| `prom-dashboard.johnisah.org` | A | `<static_ip>` | No | Prometheus UI |

---

## 14. Design Decisions

**Three-stage pipeline**: Allows each stage to be validated and debugged independently before proceeding. Running all five modules in a single apply would make failures hard to attribute.

**Minikube on GCE (not GKE)**: Dev/staging environment. GKE would cost ~$70–100/month for a comparable cluster; this setup runs on a single `e2-standard-4` VM for a fraction of that cost.

**Docker driver for Minikube**: No nested virtualization is available on GCP VMs, ruling out KVM. The Docker driver is lightweight and well-supported.

**containerd runtime**: Preferred over Docker-in-Docker inside Minikube for performance and compatibility with modern Kubernetes tooling.

**NGINX at host level**: Bridges the gap between external ports 80/443 and Minikube NodePorts 30080/30443 without needing `minikube tunnel` or privileged port access.

**Traefik before cert-manager**: cert-manager's HTTP-01 ClusterIssuer solver requires an IngressController to already exist when the ClusterIssuer is created. Installing Traefik first ensures the challenge route is available immediately.

**DNS-only for WebSocket services**: Cloudflare's reverse proxy terminates and re-establishes connections, which breaks long-lived WebSocket connections used by ArgoCD, Grafana, and Prometheus. These records bypass the proxy.

**Pinned tool versions**: Prevents silent breakage from upstream version changes. All version pins are tested together and updated deliberately.

**Infisical operator over static secrets**: Application secrets are not committed to Git or baked into Terraform state. The operator syncs them at runtime from Infisical SaaS, enabling secret rotation without redeployment.

**App of Apps pattern**: A single root `Application` pointing to `k8s/argocd/` means adding a new workload to the cluster requires only a new file in that directory — no Terraform changes needed.

**Idempotent provisioning scripts**: Every conditional in `init.sh` and `bootstrap.sh` checks before acting (`command -v`, `helm status`, `kubectl get`). The scripts can be re-run safely without duplicating resources.

**Sensitive data in temp files, not env vars or CLI args**: Infisical credentials are written to `/tmp/.bootstrap_env` and sourced by the script, never passed as CLI arguments (which would appear in process listings). The file is deleted at script completion.

---

## 15. Troubleshooting

### `terraform init` fails: credentials not found

```
Error: Failed to get existing workspaces: storage: credentials not found
```

Ensure the environment variable is set and points to a valid file:
```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp/portfolio-mcs-terraform-sa-key.json
ls -la $GOOGLE_APPLICATION_CREDENTIALS
```

### `cluster_init` fails mid-run

The script is idempotent. Check the log on the VM:
```bash
ssh -i ~/.ssh/ssh-key-2026-03-23.key isahjohna@<static_ip> "cat /tmp/init.log"
```

Re-apply only the cluster_init module after fixing the issue:
```bash
terraform apply -target=module.cluster_init
```

### Kubernetes/Helm provider fails: kubeconfig not found

`cluster_init` must complete before Stage 3. The kubeconfig at `.kube/devops-minikube.yaml` is written by `init.sh`. If it is missing, re-run Stage 2:
```bash
terraform apply -target=module.cluster_init
```

### `cluster_bootstrap` fails: cert-manager CRDs not ready

cert-manager CRD installation can take 30–60 seconds after the Helm release returns. The script waits for all three deployments; if it times out, the most common cause is a resource-constrained Minikube node. Check node status:
```bash
kubectl --kubeconfig=.kube/devops-minikube.yaml get nodes
kubectl --kubeconfig=.kube/devops-minikube.yaml -n cert-manager get pods
```

### ArgoCD shows `ComparisonError`: repo not accessible

ArgoCD must be able to reach the GitHub repo URL in `argocd_repo_url`. If the repo is private, an SSH deploy key or HTTPS token needs to be configured in the ArgoCD repository settings before the root Application is applied.

### DNS records created but site not reachable

1. Check DNS propagation: `dig +short <hostname>`
2. Verify NGINX is running on the VM: `ssh isahjohna@<ip> "sudo systemctl status nginx"`
3. Verify Minikube is up: `ssh isahjohna@<ip> "minikube status -p devops-minikube"`
4. Check Traefik pods: `kubectl --kubeconfig=.kube/devops-minikube.yaml -n traefik get pods`

### Retrieve ArgoCD admin password

```bash
kubectl --kubeconfig=.kube/devops-minikube.yaml \
  -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### View bootstrap logs on the VM

```bash
ssh -i ~/.ssh/ssh-key-2026-03-23.key isahjohna@<static_ip> "cat /tmp/bootstrap.log"
```
