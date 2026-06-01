# Backup System — Quick Start Guide

## What Gets Backed Up?

✅ **Database** (portfolio_db) — Daily at 02:00 UTC  
✅ **Secrets & ConfigMaps** — Daily at 03:00 UTC  
✅ **Monitoring Data** (Prometheus & Grafana) — Daily at 04:00 UTC  
✅ **Monitoring Config** (dashboards, datasources) — As part of Secrets/ConfigMaps  

## Installation (One-Time Setup)

```bash
# 1. Deploy backup infrastructure to cluster
kubectl apply -f k8s/backup/

# 2. Verify deployment
kubectl get ns backup
kubectl get cronjobs -n backup

# 3. Make backup manager script available
chmod +x scripts/backup-manager.sh
```

## Common Tasks

### Check Backup Status

```bash
./scripts/backup-manager.sh status
```

**Output:**
```
ℹ Backup Infrastructure Status

✓ Backup namespace exists

ℹ CronJob Status:
NAME                          SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE
backup-configmaps-secrets     0 3 * * *   False     0        ...
portfolio-db-backup           0 2 * * *   False     0        ...

ℹ Recent Backup Jobs (last 7 days):
...

ℹ Backup Storage:
NAME                    STATUS   VOLUME                  CAPACITY
backup-storage-pvc      Bound    pvc-xxxxx               10Gi

ℹ Storage Usage:
Total: 234M
Database backups:
portfolio_db_20260424_020000.sql.gz (89M)
portfolio_db_20260423_020001.sql.gz (78M)
...
```

### List Available Backups

```bash
./scripts/backup-manager.sh list
```

### Trigger Manual Backup

```bash
# Backup database
./scripts/backup-manager.sh trigger db

# Backup secrets/configs
./scripts/backup-manager.sh trigger config

# Monitor the job
./scripts/backup-manager.sh logs db
```

### Download Backup File

```bash
./scripts/backup-manager.sh download portfolio_db_20260424_020000.sql.gz

# File will be saved to current directory
ls -lh portfolio_db_*.sql.gz
```

### Restore Database

```bash
# First, upload the backup file if needed
./scripts/backup-manager.sh upload /path/to/backup.sql.gz

# Then restore
./scripts/backup-manager.sh restore portfolio_db_20260424_020000.sql.gz

# Monitor restoration
./scripts/backup-manager.sh logs all
```

### Verify Backup Integrity

```bash
./scripts/backup-manager.sh verify portfolio_db_20260424_020000.sql.gz
```

## Before VM Migration

**Day before:**

1. Check backup status
   ```bash
   ./scripts/backup-manager.sh status
   ```

2. Ensure recent backups exist (all 3 types)
   ```bash
   ./scripts/backup-manager.sh list
   # Should show:
   # - Database backup (portfolio_db_...sql.gz)
   # - Config backup (configs_...tar.gz)
   # - Monitoring backups (prometheus_*.tar.gz, grafana_*.tar.gz)
   ```

3. Download all backups
   ```bash
   ./scripts/backup-manager.sh download portfolio_db_20260424_020000.sql.gz
   ./scripts/backup-manager.sh download configs_20260424_030000.tar.gz
   ./scripts/backup-manager.sh download monitoring/prometheus_20260424_040000.tar.gz
   ./scripts/backup-manager.sh download monitoring/grafana_20260424_040000.tar.gz
   ```

4. Store backups externally (USB, S3, etc.)

**During migration:**

1. Disable automatic backups (optional, to avoid failures)
   ```bash
   ./scripts/backup-manager.sh disable
   ```

2. Note backup file locations (saved from step 3 above)

**After new cluster setup:**

1. Deploy backup system
   ```bash
   kubectl apply -f k8s/backup/
   ```

2. Upload all backup files
   ```bash
   ./scripts/backup-manager.sh upload /path/to/portfolio_db_20260424_020000.sql.gz
   ./scripts/backup-manager.sh upload /path/to/configs_20260424_030000.tar.gz
   ./scripts/backup-manager.sh upload /path/to/prometheus_20260424_040000.tar.gz
   ./scripts/backup-manager.sh upload /path/to/grafana_20260424_040000.tar.gz
   ```

3. Restore database
   ```bash
   ./scripts/backup-manager.sh restore portfolio_db_20260424_020000.sql.gz
   ```

4. Restore monitoring data
   ```bash
   # Restore Prometheus
   kubectl exec -it -n backup <backup-pod> -- bash
   # cd /backups/monitoring && tar xzf prometheus_*.tar.gz
   
   # Restore Grafana
   # kubectl exec -n monitoring <grafana-pod> -- tar xzf - -C /var/lib/grafana < prometheus_*.tar.gz
   ```

5. Verify restoration
   ```bash
   # Check database
   kubectl exec -it -n portfolio portfolio-db-0 -- \
     psql -U portfolio_user -d portfolio_db \
     -c "SELECT COUNT(*) FROM visitor_logs;"
   
   # Check Prometheus metrics
   kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
   # Open http://localhost:9090 and check metrics
   
   # Check Grafana dashboards
   kubectl port-forward -n monitoring svc/grafana 3000:3000 &
   # Open http://localhost:3000 and verify dashboards
   ```

6. Enable automatic backups
   ```bash
   ./scripts/backup-manager.sh enable
   ```

## Backup Schedule

| What | When | Frequency | Size | Retention |
|------|------|-----------|------|-----------|
| **Database** | 02:00 UTC daily | Daily | ~100-500 MB | 7 days |
| **Secrets/Configs** | 03:00 UTC daily | Daily | ~5-10 MB | 14 days || **Prometheus Data** | 04:00 UTC daily | Daily | ~2-4 GB | 14 days |
| **Grafana Data** | 04:00 UTC daily | Daily | ~200-500 MB | 14 days |
## Change Backup Schedule

Edit the CronJob schedule in [k8s/backup/03-cronjob-db-backup.yaml](k8s/backup/03-cronjob-db-backup.yaml):

```yaml
spec:
  schedule: "0 2 * * *"  # Change this
```

Cron format: `minute hour day month day-of-week`

- `0 2 * * *` = Daily at 02:00 UTC
- `0 0 * * 0` = Weekly (Sunday at 00:00 UTC)
- `0 */6 * * *` = Every 6 hours

Apply changes:
```bash
kubectl apply -f k8s/backup/03-cronjob-db-backup.yaml
```

## Troubleshooting

### Backup job stuck or failing

```bash
# Check job status
kubectl get jobs -n backup

# View detailed logs
./scripts/backup-manager.sh logs all

# Common issues:
# 1. Database not responding
kubectl get pod -n portfolio portfolio-db-0
kubectl logs -n portfolio portfolio-db-0

# 2. Storage full
./scripts/backup-manager.sh status | grep "Storage Usage"

# 3. Credentials wrong
kubectl get secret -n portfolio portfolio-secrets -o yaml
```

### Can't restore database

```bash
# Verify backup file exists
./scripts/backup-manager.sh list

# Verify integrity
./scripts/backup-manager.sh verify portfolio_db_20260424_020000.sql.gz

# Check database is empty/fresh
kubectl exec -it -n portfolio portfolio-db-0 -- \
  psql -U portfolio_user -d portfolio_db -c "SELECT COUNT(*) FROM visitor_logs;"

# View restore logs
kubectl logs -n backup restore-db-* --all-containers=true
```

## Storage Management

### Current allocation: 10Gi

Estimated space usage:
- Database backup: ~100-500 MB per day
- Config backup: ~5-10 MB per day
- **Total/week:** ~750 MB - 3.5 GB
- **Current retention:** 7 days for DB, 14 days for configs

If backups are growing beyond 10Gi:

1. Reduce retention period in CronJob
2. Or increase PVC size:
   ```bash
   kubectl patch pvc backup-storage-pvc -n backup -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
   ```

## See Also

- [Full Backup Strategy](./BACKUP_STRATEGY.md) — Detailed architecture and recovery procedures
- [Kubernetes Documentation](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-cluster/) — Cluster upgrade/migration guides
