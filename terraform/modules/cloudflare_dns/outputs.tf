output "hostnames" {
  description = "All DNS record hostnames created in Cloudflare."
  value = {
    root          = cloudflare_record.root.hostname
    www           = cloudflare_record.www.hostname
    api           = cloudflare_record.api.hostname
    admin         = cloudflare_record.admin.hostname
    argocd        = cloudflare_record.argocd.hostname
    shopnow       = cloudflare_record.shopnow.hostname
    grafana       = cloudflare_record.grafana.hostname
    prom_dashboard = cloudflare_record.prom_dashboard.hostname
  }
}
