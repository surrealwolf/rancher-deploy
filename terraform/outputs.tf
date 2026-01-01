output "rancher_manager_ip" {
  description = "Rancher manager cluster IP addresses"
  value       = values(module.rancher_manager)[*].ip_address
}

output "rancher_manager_url" {
  description = "Rancher manager URL"
  value       = "https://${var.rancher_hostname}"
}

output "nprd_apps_cluster_ips" {
  description = "NPRD apps cluster IP addresses"
  value       = values(module.nprd_apps)[*].ip_address
}

output "cluster_kubeconfigs" {
  description = "Kubeconfig paths for clusters"
  value = {
    manager   = "Local kubeconfig will be generated post-deployment"
    nprd_apps = "Local kubeconfig will be generated post-deployment"
  }
}
