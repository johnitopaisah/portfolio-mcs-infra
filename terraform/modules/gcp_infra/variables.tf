variable "project" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for the subnet and static IP."
}

variable "zone" {
  type        = string
  description = "GCP zone for the GCE instance. Must be within var.region."
}

variable "machine_type" {
  type        = string
  description = "GCE machine type (e.g. e2-standard-2)."
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB."
  default     = 50
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key injected as the isahjohna user in VM metadata."
}

variable "ssh_source_ranges" {
  type        = list(string)
  description = "CIDR ranges permitted to reach the VM on port 22."
}

variable "common_labels" {
  type        = map(string)
  description = "Labels applied to every resource in this module."
  default     = {}
}
