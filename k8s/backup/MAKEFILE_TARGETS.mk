# ============================================================
#  Makefile targets for backup operations
#  Add to: Makefile (in root directory)
# ============================================================

.PHONY: backup-setup backup-status backup-list backup-trigger backup-download backup-restore backup-enable backup-disable

BACKUP_SCRIPT := scripts/backup-manager.sh

# Deploy backup infrastructure
backup-setup:
	@echo "Deploying backup infrastructure..."
	@kubectl apply -f k8s/backup/
	@echo ""
	@$(MAKE) backup-status

# Show backup status
backup-status:
	@$(BACKUP_SCRIPT) status

# List available backups
backup-list:
	@$(BACKUP_SCRIPT) list

# Trigger manual database backup
backup-trigger-db:
	@$(BACKUP_SCRIPT) trigger db

# Trigger manual config backup
backup-trigger-config:
	@$(BACKUP_SCRIPT) trigger config

# Trigger manual monitoring backup
backup-trigger-monitoring:
	@kubectl create job --from=cronjob/backup-monitoring-volumes \
	  manual-monitoring-backup-$$(date +%s) -n backup
	@echo "Monitoring backup triggered"

# View backup logs
backup-logs:
	@$(BACKUP_SCRIPT) logs all

# Enable automatic backups
backup-enable:
	@$(BACKUP_SCRIPT) enable
	@echo "Automatic backups enabled"

# Disable automatic backups (e.g., during migration)
backup-disable:
	@$(BACKUP_SCRIPT) disable
	@echo "Automatic backups disabled"

# Show backup schedule
backup-schedule:
	@$(BACKUP_SCRIPT) schedule

# Pre-migration checklist
backup-pre-migration: backup-disable
	@echo ""
	@echo "Pre-Migration Checklist:"
	@echo "  [ ] Download backup files (backup-download-latest)"
	@echo "  [ ] Verify backup integrity (backup-verify-latest)"
	@echo "  [ ] Store backups securely (USB/S3/external storage)"
	@echo "  [ ] Note backup file paths"
	@echo ""
	@echo "After new cluster is ready, restore with:"
	@echo "  make backup-setup"
	@echo "  make backup-upload-from=<path>"
	@echo "  make backup-restore-from=<filename>"

# View deployment guide
backup-help:
	@cat k8s/backup/README.md

# Advanced: Download latest database backup
backup-download-latest:
	@LATEST=$$(kubectl get pod -n backup -l app=portfolio-mcs -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	BACKUP=$$(kubectl exec -n backup $$LATEST -- ls -t /backups/portfolio_db_*.sql.gz 2>/dev/null | head -1); \
	if [ -n "$$BACKUP" ]; then \
	  $(BACKUP_SCRIPT) download $$(basename $$BACKUP); \
	else \
	  echo "No backups found"; \
	fi

# Advanced: Verify latest backup
backup-verify-latest:
	@LATEST=$$(kubectl get pod -n backup -l app=portfolio-mcs -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	BACKUP=$$(kubectl exec -n backup $$LATEST -- ls -t /backups/portfolio_db_*.sql.gz 2>/dev/null | head -1); \
	if [ -n "$$BACKUP" ]; then \
	  $(BACKUP_SCRIPT) verify $$(basename $$BACKUP); \
	else \
	  echo "No backups found"; \
	fi

# Advanced: Upload backup file for restoration
backup-upload-from:
	@if [ -z "$(from)" ]; then \
	  echo "Usage: make backup-upload-from=<path/to/backup.sql.gz>"; \
	  exit 1; \
	fi
	@$(BACKUP_SCRIPT) upload "$(from)"

# Advanced: Restore from backup file
backup-restore-from:
	@if [ -z "$(from)" ]; then \
	  echo "Usage: make backup-restore-from=<filename>"; \
	  exit 1; \
	fi
	@$(BACKUP_SCRIPT) restore "$(from)"

# Add to main help text
help-backup:
	@echo ""
	@echo "Backup Management:"
	@echo "  make backup-setup           - Deploy backup infrastructure"
	@echo "  make backup-status          - Show backup status"
	@echo "  make backup-list            - List available backups"
	@echo "  make backup-trigger-db      - Trigger manual database backup"
	@echo "  make backup-trigger-config  - Trigger manual config backup"
	@echo "  make backup-logs            - View recent backup logs"
	@echo "  make backup-enable          - Enable automatic backups"
	@echo "  make backup-disable         - Disable automatic backups"
	@echo "  make backup-schedule        - Show backup schedule"
	@echo "  make backup-help            - Display full backup guide"
	@echo "  make backup-pre-migration   - Pre-migration checklist"
	@echo ""
