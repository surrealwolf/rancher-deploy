output "rancher_manager_ip" {
  description = "Rancher manager cluster IP addresses"
  value       = module.rancher_manager.cluster_ips
}

output "rancher_manager_url" {
  description = "Rancher manager URL"
  value       = "https://${var.rancher_hostname}"
}

output "nprd_apps_cluster_ips" {
  description = "NPRD apps cluster IP addresses"
  value       = module.nprd_apps.cluster_ips
}

output "cluster_kubeconfigs" {
  description = "Kubeconfig paths for clusters"
  value = {
    manager   = module.rancher_manager.kubeconfig_path
    nprd_apps = module.nprd_apps.kubeconfig_path
  }
}
