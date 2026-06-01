# Remote state stored in GCS.
# The bucket must be created manually before running `terraform init`.
# See TERRAFORM_PLAN.md § Prerequisites › GCS State Bucket for instructions.
#
# Backend blocks cannot use variables. Credentials are resolved in this order:
#   1. GOOGLE_APPLICATION_CREDENTIALS env var (recommended — works across machines)
#   2. The credentials attribute below (machine-specific path, use as fallback)
#
# Recommended: set once in ~/.zshrc and never touch this file:
#   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/terraform-sa-key.json
terraform {
  backend "gcs" {
    bucket = "portfolio-mcs-prod-tfstate"
    prefix = "portfolio-mcs/state"

    credentials = "/Users/isahjohna/.gcp/portfolio-mcs-terraform-sa-key.json"
  }
}
