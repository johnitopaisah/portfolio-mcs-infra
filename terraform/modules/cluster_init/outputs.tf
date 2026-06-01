output "complete" {
  value       = null_resource.cluster_init.id
  description = "Non-null once cluster_init has run. Used as a depends_on anchor by cluster_bootstrap."
}
