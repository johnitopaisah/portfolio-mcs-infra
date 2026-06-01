variable "zone_id" {
  type        = string
  description = "Cloudflare Zone ID for johnisah.org."
}

variable "vm_ip" {
  type        = string
  description = "Static external IP of devops-instance. All A records point here."
}
