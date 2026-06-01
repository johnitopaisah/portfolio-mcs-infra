# ── Root domain (@) ──────────────────────────────────────────────────────────────
# Proxied through Cloudflare for DDoS protection and CDN caching.
# TTL = 1 means "Auto" — required when proxied = true.
resource "cloudflare_record" "root" {
  zone_id = var.zone_id
  name    = "@"
  type    = "A"
  content = var.vm_ip
  proxied = true
  ttl     = 1
}

# ── www ──────────────────────────────────────────────────────────────────────────
resource "cloudflare_record" "www" {
  zone_id = var.zone_id
  name    = "www"
  type    = "CNAME"
  content = "johnisah.org"
  proxied = true
  ttl     = 1
}

# ── api ──────────────────────────────────────────────────────────────────────────
resource "cloudflare_record" "api" {
  zone_id = var.zone_id
  name    = "api"
  type    = "A"
  content = var.vm_ip
  proxied = true
  ttl     = 1
}

# ── admin ────────────────────────────────────────────────────────────────────────
resource "cloudflare_record" "admin" {
  zone_id = var.zone_id
  name    = "admin"
  type    = "A"
  content = var.vm_ip
  proxied = true
  ttl     = 1
}

# ── argocd-deploy ────────────────────────────────────────────────────────────────
# DNS-only (not proxied). ArgoCD uses WebSockets — Cloudflare proxy can break them.
# TTL 300 = 5 minutes, fast propagation during initial setup.
resource "cloudflare_record" "argocd" {
  zone_id = var.zone_id
  name    = "argocd-deploy"
  type    = "A"
  content = var.vm_ip
  proxied = false
  ttl     = 300
}

# ── shopnow ──────────────────────────────────────────────────────────────────────
resource "cloudflare_record" "shopnow" {
  zone_id = var.zone_id
  name    = "shopnow"
  type    = "A"
  content = var.vm_ip
  proxied = true
  ttl     = 1
}

# ── grafana ──────────────────────────────────────────────────────────────────────
# DNS-only — Grafana uses WebSockets for live dashboard updates.
resource "cloudflare_record" "grafana" {
  zone_id = var.zone_id
  name    = "grafana"
  type    = "A"
  content = var.vm_ip
  proxied = false
  ttl     = 300
}

# ── prom-dashboard ───────────────────────────────────────────────────────────────
# DNS-only — internal tooling, no Cloudflare proxy needed.
resource "cloudflare_record" "prom_dashboard" {
  zone_id = var.zone_id
  name    = "prom-dashboard"
  type    = "A"
  content = var.vm_ip
  proxied = false
  ttl     = 300
}
