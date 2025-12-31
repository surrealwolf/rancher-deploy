terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure = var.proxmox_tls_insecure
}

module "rancher_infrastructure" {
  source = "../../"

  # Proxmox Configuration
  proxmox_api_url     = var.proxmox_api_url
  proxmox_token_id    = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_tls_insecure = var.proxmox_tls_insecure
  proxmox_node        = var.proxmox_node
  vm_template_id      = var.vm_template_id
  ssh_private_key     = var.ssh_private_key

  # Cluster Configuration
  clusters = {
    manager = {
      name         = "rancher-manager"
      node_count   = 3
      cpu_cores    = 4
      memory_mb    = 8192
      disk_size_gb = 100
      domain       = var.domain
      ip_subnet    = "192.168.1.0/24"
      gateway      = "192.168.1.1"
      dns_servers  = var.dns_servers
      storage      = var.storage
    }
    nprd-apps = {
      name         = "nprd-apps"
      node_count   = 3
      cpu_cores    = 8
      memory_mb    = 16384
      disk_size_gb = 150
      domain       = var.domain
      ip_subnet    = "192.168.2.0/24"
      gateway      = "192.168.1.1"
      dns_servers  = var.dns_servers
      storage      = var.storage
    }
  }

  # Rancher Configuration
  rancher_version  = var.rancher_version
  rancher_password = var.rancher_password
  rancher_hostname = var.rancher_hostname
}

output "cluster_ips" {
  description = "Cluster node IP addresses"
  value       = module.rancher_infrastructure.cluster_ips
}

output "kubeconfig_paths" {
  description = "Kubeconfig file paths"
  value       = module.rancher_infrastructure.kubeconfig_path
}

output "rancher_url" {
  description = "Rancher manager URL"
  value       = "https://${var.rancher_hostname}"
}
