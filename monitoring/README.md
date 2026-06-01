# Monitoring & Observability

Production-grade observability stack for Portfolio MCS. Runs in the `monitoring` namespace on the same cluster as the application.

- **Grafana:** https://grafana.johnisah.com
- **Prometheus:** internal (port-forward to access: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`)
- **Alertmanager:** internal (port-forward: `kubectl port-forward -n monitoring svc/alertmanager 9093:9093`)

---

## Components

| Component | Image | Purpose |
|---|---|---|
| Prometheus | `prom/prometheus:v2.51.0` | Time-series metrics store, 30-day retention, 5Gi PVC |
| Grafana | `grafana/grafana:10.4.0` | 7 dashboards at grafana.johnisah.com, 2Gi PVC |
| Alertmanager | `prom/alertmanager:v0.27.0` | Routes alerts → email via Zoho SMTP |
| node-exporter | `prom/node-exporter:v1.7.0` | DaemonSet — OS/hardware metrics from all nodes |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.12.0` | Kubernetes object state |
| postgres-exporter | `quay.io/prometheuscommunity/postgres-exporter:v0.15.0` | PostgreSQL internals |

---

## Directory structure

```
monitoring/
├── README.md
├── api/
│   ├── metrics.js                  Reference copy of API Prometheus metric definitions
│   └── middleware.js               Reference copy of API metrics middleware
│
├── argocd/                         ArgoCD Application CRDs for the monitoring stack
│   ├── project.yaml
│   ├── app-prometheus.yaml
│   ├── app-grafana.yaml
│   ├── app-alertmanager.yaml
│   ├── app-exporters.yaml
│   ├── app-infisical.yaml
│   └── app-policies.yaml
│
├── infisical/                      Infisical CRDs — syncs monitoring secrets
│   ├── 01-grafana-secret.yaml      → grafana-admin-secret
│   ├── 02-alertmanager-secret.yaml → alertmanager-smtp-secret
│   └── 03-postgres-exporter-secret.yaml → postgres-exporter-secret
│
├── prometheus/
│   ├── 00-namespace.yaml
│   ├── 01-rbac.yaml                ClusterRole to scrape all namespaces
│   ├── 02-configmap.yaml           prometheus.yml scrape config + alert rules
│   ├── 03-pvc.yaml                 5Gi persistent volume
│   ├── 04-statefulset.yaml
│   ├── 05-service.yaml
│   ├── 06-ingress.yaml
│   └── backup-manager.sh
│
├── grafana/
│   ├── 00-serviceaccount.yaml
│   ├── 01-pvc.yaml                 2Gi persistent volume
│   ├── 03-configmap-datasources.yaml   Prometheus datasource (auto-provisioned)
│   ├── 04-configmap-dashboard-provider.yaml
│   ├── 05-deployment.yaml
│   ├── 06-service.yaml
│   ├── 07-ingress.yaml             grafana.johnisah.com, TLS via cert-manager
│   ├── DASHBOARD_GUIDE.md
│   └── dashboards/
│       ├── 01-system-overview.yaml
│       ├── 02-api-performance.yaml
│       ├── 03-database-health.yaml
│       ├── 04-infrastructure.yaml
│       ├── 05-business-metrics.yaml
│       ├── 06-alerts-slo.yaml
│       └── 07-visitor-analytics.yaml
│
├── alertmanager/
│   ├── 01-serviceaccount.yaml
│   ├── 01-configmap.yaml           Routing rules + Zoho SMTP receiver
│   ├── 03-deployment.yaml
│   └── 04-service.yaml
│
└── exporters/
    ├── node-exporter/
    │   ├── 01-serviceaccount.yaml
    │   ├── 02-daemonset.yaml       One pod per node
    │   └── 03-service.yaml
    ├── kube-state-metrics/
    │   └── 01-all.yaml             RBAC + Deployment + Service
    └── postgres-exporter/
        ├── 01-serviceaccount.yaml
        └── 02-deployment.yaml
```

---

## Grafana dashboards

| # | Dashboard | Key panels |
|---|---|---|
| 1 | **System Overview** | Pod health, API error rate, DB connections, node CPU — at-a-glance summary |
| 2 | **API Performance** | Request rate, P50/P95/P99 latency, error rate by route, top slow routes |
| 3 | **Database Health** | Active connections, cache hit ratio, query duration, dead tuple rate, table sizes |
| 4 | **Infrastructure** | Node CPU/memory/disk per node, pod resource consumption, PVC usage |
| 5 | **Business Metrics** | Contact form submissions, auth events, project views, content update activity |
| 6 | **Alerts & SLO** | Active alerts by severity, 30-day availability SLO, error budget burn rate |
| 7 | **Visitor Analytics** | Unique visitors, top countries, top pages, referrer breakdown, session trends |

---

## Secrets strategy

All secrets in the `monitoring` namespace are managed by the Infisical operator — no passwords in git.

### Required Infisical secrets (path: `/monitoring`, env: `prod`)

| Key | Creates K8s secret | Notes |
|---|---|---|
| `GRAFANA_ADMIN_USER` | `grafana-admin-secret` → `admin-user` | Use `admin` |
| `GRAFANA_ADMIN_PASSWORD` | `grafana-admin-secret` → `admin-password` | 16+ chars |
| `ALERTMANAGER_SMTP_PASSWORD` | `alertmanager-smtp-secret` → `smtp-password` | Zoho app password |
| `MONITORING_DB_DSN` | `postgres-exporter-secret` → `DATA_SOURCE_NAME` | Full `postgresql://` DSN |

---

## Deployment walkthrough

### Prerequisites

1. `monitoring` namespace exists (created by `monitoring/prometheus/00-namespace.yaml`)
2. Infisical machine identity secret exists in the `monitoring` namespace:

```bash
# Copy from the portfolio namespace (same identity)
CLIENT_ID=$(kubectl get secret infisical-machine-identity -n portfolio \
  -o jsonpath='{.data.clientId}' | base64 -d)
CLIENT_SECRET=$(kubectl get secret infisical-machine-identity -n portfolio \
  -o jsonpath='{.data.clientSecret}' | base64 -d)

kubectl create secret generic infisical-machine-identity \
  --namespace monitoring \
  --from-literal=clientId="$CLIENT_ID" \
  --from-literal=clientSecret="$CLIENT_SECRET"
```

### Via ArgoCD (recommended)

```bash
# Apply the monitoring root app — ArgoCD syncs everything
kubectl apply -f k8s/argocd/app-monitoring-root.yaml
```

### Manual apply order

```bash
kubectl apply -f monitoring/prometheus/00-namespace.yaml
kubectl apply -f monitoring/infisical/
kubectl apply -f monitoring/prometheus/01-rbac.yaml
kubectl apply -f monitoring/prometheus/02-configmap.yaml
kubectl apply -f monitoring/prometheus/03-pvc.yaml
kubectl apply -f monitoring/prometheus/04-statefulset.yaml
kubectl apply -f monitoring/prometheus/05-service.yaml
kubectl apply -f monitoring/exporters/node-exporter/
kubectl apply -f monitoring/exporters/kube-state-metrics/
kubectl apply -f monitoring/exporters/postgres-exporter/
kubectl apply -f monitoring/alertmanager/
kubectl apply -f monitoring/grafana/
```

---

## Prometheus scrape targets

After deployment, all these targets should show **UP** at `http://localhost:9090/targets`:

| Job | Expected instances |
|---|---|
| `prometheus` | 1 |
| `portfolio-api` | 2 (matching replica count) |
| `node-exporter` | 1 per node |
| `kube-state-metrics` | 1 |
| `postgres-exporter` | 1 |

---

## Alert rules

Alerts are defined in `monitoring/prometheus/02-configmap.yaml` and routed to Alertmanager → Zoho SMTP → `connect@johnisah.com`.

| Alert | Condition | Severity |
|---|---|---|
| `APIHighErrorRate` | HTTP 5xx rate > 5% for 5 min | critical |
| `APIHighLatency` | P99 latency > 2s for 5 min | warning |
| `PodCrashLooping` | Pod restart rate > 0.2/min | critical |
| `NodeHighCPU` | Node CPU > 85% for 10 min | warning |
| `NodeHighMemory` | Node memory > 90% for 10 min | warning |
| `PostgreSQLDown` | postgres-exporter target DOWN | critical |
| `DiskSpaceLow` | PVC usage > 80% | warning |

---

## Quick health check

```bash
# All monitoring pods
kubectl get pods -n monitoring

# Infisical sync status
kubectl get infisicalsecrets -n monitoring

# Prometheus targets (requires port-forward)
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Alertmanager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Infisical secret not created after 60s | Operator can't authenticate | `kubectl describe infisicalsecret <name> -n monitoring` |
| `portfolio-api` target DOWN | Network policy blocking port 4000 | Apply `k8s/policies/04-network-policy.yaml` |
| `postgres-exporter` CrashLoopBackOff | Wrong DSN or monitoring user missing | Verify `monitoring_user` exists in DB; check DSN in Infisical |
| Grafana shows "No Data" | Wrong Prometheus datasource URL | Datasource URL must be `http://prometheus:9090` |
| Grafana stuck in ContainerCreating | PVC not bound | `kubectl get pvc -n monitoring` — check storageClass |
| node-exporter pod count < node count | DaemonSet tolerations missing | `kubectl describe ds node-exporter -n monitoring` |
| Alertmanager not sending email | SMTP auth failed | `kubectl logs -n monitoring deploy/alertmanager` |
