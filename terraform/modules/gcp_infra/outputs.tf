output "static_ip" {
  value       = google_compute_address.static_ip.address
  description = "Static external IP of devops-instance. All DNS records point here."
}

output "instance_name" {
  value       = google_compute_instance.devops_instance.name
  description = "GCE instance name."
}

output "instance_zone" {
  value       = google_compute_instance.devops_instance.zone
  description = "GCE zone where the instance was created."
}

output "vm_sa_email" {
  value       = google_service_account.vm_sa.email
  description = "Email of the service account attached to the VM."
}
