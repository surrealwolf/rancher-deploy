output "rancher_manager_primary_ip" {
  description = "Rancher manager primary node IP (manager-1)"
  value       = split("/", module.rancher_manager_primary.ip_address)[0]
}

output "rancher_manager_additional_ips" {
  description = "Rancher manager additional nodes IPs (manager-2, manager-3)"
  value       = {
    for name, node in module.rancher_manager_additional :
    name => split("/", node.ip_address)[0]
  }
}

output "rancher_manager_cluster_ips" {
  description = "All Rancher manager cluster IP addresses"
  value       = concat(
    [split("/", module.rancher_manager_primary.ip_address)[0]],
    [for node in module.rancher_manager_additional : split("/", node.ip_address)[0]]
  )
}

output "nprd_apps_primary_ip" {
  description = "NPRD apps primary node IP (apps-1)"
  value       = split("/", module.nprd_apps_primary.ip_address)[0]
}

output "nprd_apps_additional_ips" {
  description = "NPRD apps additional nodes IPs (apps-2, apps-3)"
  value       = {
    for name, node in module.nprd_apps_additional :
    name => split("/", node.ip_address)[0]
  }
}

output "nprd_apps_cluster_ips" {
  description = "All NPRD apps cluster IP addresses"
  value       = concat(
    [split("/", module.nprd_apps_primary.ip_address)[0]],
    [for node in module.nprd_apps_additional : split("/", node.ip_address)[0]]
  )
}

output "rancher_manager_url" {
  description = "Rancher manager URL"
  value       = "https://${var.rancher_hostname}"
}

output "rancher_deployment_status" {
  description = "Rancher deployment information"
  value = {
    enabled      = var.install_rancher
    hostname     = var.rancher_hostname
    version      = var.rancher_version
    access_url   = var.install_rancher ? "https://${var.rancher_hostname}" : "Not deployed"
    admin_user   = "admin"
    bootstrap_pw = var.install_rancher ? "Use rancher_password from tfvars" : "N/A"
  }
}

output "manager_kubeconfig_path" {
  description = "Path to manager cluster kubeconfig"
  value       = module.rke2_manager.kubeconfig_path
}

output "apps_cluster_info" {
  description = "Apps cluster deployment info"
  value = {
    cluster_name = module.rke2_apps.cluster_name
    agent_count  = module.rke2_apps.agent_count
    primary_ip   = split("/", module.nprd_apps_primary.ip_address)[0]
    secondary_ips = [for node in module.nprd_apps_additional : split("/", node.ip_address)[0]]
  }
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOT
    ✓ Deployment Complete!
    
    Manager Cluster (HA RKE2):
      Primary:    ${split("/", module.rancher_manager_primary.ip_address)[0]}
      Secondary:  ${join(", ", [for node in module.rancher_manager_additional : split("/", node.ip_address)[0]])}
      Kubeconfig: ${module.rke2_manager.kubeconfig_path}
      API Server: ${module.rke2_manager.api_server_url}
    
    Apps Cluster (HA RKE2 - Downstream):
      Primary:    ${split("/", module.nprd_apps_primary.ip_address)[0]}
      Secondary:  ${join(", ", [for node in module.nprd_apps_additional : split("/", node.ip_address)[0]])}
      Cluster:    ${module.rke2_apps.cluster_name} (${module.rke2_apps.agent_count} nodes)
    
    Next Steps:
      1. Verify manager cluster: kubectl --kubeconfig=~/.kube/rancher-manager.yaml get nodes
      2. Verify apps nodes are provisioned: Check Proxmox UI
      3. Deploy Rancher: See docs/RANCHER_DEPLOYMENT.md
      4. Monitor RKE2: ssh ubuntu@<ip> sudo systemctl status rke2-server
  EOT
}
