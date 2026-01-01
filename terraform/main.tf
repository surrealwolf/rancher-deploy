module "rancher_manager" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(var.clusters["manager"].node_count) :
    "manager-${i + 1}" => {
      vm_id      = 401 + i
      hostname   = "rancher-manager-${i + 1}"
      ip_address = "${var.clusters["manager"].ip_subnet}.${var.clusters["manager"].ip_start_octet + i}/24"
    }
  }

  vm_name         = each.value.hostname
  vm_id           = each.value.vm_id
  proxmox_node    = var.proxmox_node
  cloud_image_url = var.ubuntu_cloud_image_url
  datastore_id    = var.clusters["manager"].storage

  cpu_cores    = var.clusters["manager"].cpu_cores
  memory_mb    = var.clusters["manager"].memory_mb
  disk_size_gb = var.clusters["manager"].disk_size_gb

  hostname    = each.value.hostname
  ip_address  = each.value.ip_address
  gateway     = var.clusters["manager"].gateway
  dns_servers = var.clusters["manager"].dns_servers
  domain      = var.clusters["manager"].domain
  vlan_id     = 14

  ssh_private_key = var.ssh_private_key
}

module "nprd_apps" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(var.clusters["nprd-apps"].node_count) :
    "nprd-apps-${i + 1}" => {
      vm_id      = 404 + i
      hostname   = "nprd-apps-${i + 1}"
      ip_address = "${var.clusters["nprd-apps"].ip_subnet}.${var.clusters["nprd-apps"].ip_start_octet + i}/24"
    }
  }

  vm_name         = each.value.hostname
  vm_id           = each.value.vm_id
  proxmox_node    = var.proxmox_node
  cloud_image_url = var.ubuntu_cloud_image_url
  datastore_id    = var.clusters["nprd-apps"].storage

  cpu_cores    = var.clusters["nprd-apps"].cpu_cores
  memory_mb    = var.clusters["nprd-apps"].memory_mb
  disk_size_gb = var.clusters["nprd-apps"].disk_size_gb

  hostname    = each.value.hostname
  ip_address  = each.value.ip_address
  gateway     = var.clusters["nprd-apps"].gateway
  dns_servers = var.clusters["nprd-apps"].dns_servers
  domain      = var.clusters["nprd-apps"].domain
  vlan_id     = 14

  ssh_private_key = var.ssh_private_key

  # Wait for manager nodes to complete before creating nprd-apps nodes
  depends_on = [module.rancher_manager]
}

# Deploy RKE2 on manager cluster
module "rke2_manager" {
  source = "./modules/rke2_cluster"

  cluster_name         = "rancher-manager"
  server_ips           = [for vm in module.rancher_manager : split("/", vm.ip_address)[0]]
  ssh_private_key_path = pathexpand(var.ssh_private_key)
  ssh_user             = "ubuntu"
  rke2_version         = "latest"

  depends_on = [module.rancher_manager]
}

# Deploy RKE2 on apps cluster
module "rke2_apps" {
  source = "./modules/rke2_cluster"

  cluster_name         = "nprd-apps"
  server_ips           = [for vm in module.nprd_apps : split("/", vm.ip_address)[0]]
  ssh_private_key_path = pathexpand(var.ssh_private_key)
  ssh_user             = "ubuntu"
  rke2_version         = "latest"

  depends_on = [module.nprd_apps]
}

# Deploy Rancher on manager cluster
# Enable by setting deploy_rancher = true in terraform.tfvars or via -var flag
# This will only run after RKE2 is deployed and kubeconfig is available
module "rancher_deployment" {
  source = "./modules/rancher_cluster"

  cluster_name     = "rancher-manager"
  node_count       = var.clusters["manager"].node_count
  kubeconfig_path  = pathexpand("~/.kube/rancher-manager.yaml")
  install_rancher  = var.deploy_rancher
  rancher_version  = var.rancher_version
  rancher_password = var.rancher_password
  rancher_hostname = var.rancher_hostname
}

# Create local kubeconfig files for each cluster
locals {
  manager_hosts   = [for vm in module.rancher_manager : split("/", vm.ip_address)[0]]
  nprd_apps_hosts = [for vm in module.nprd_apps : split("/", vm.ip_address)[0]]
}

output "cluster_ips" {
  value = {
    manager   = local.manager_hosts
    nprd_apps = local.nprd_apps_hosts
  }
}

output "rancher_url" {
  description = "Rancher URL"
  value       = "https://${var.rancher_hostname}"
}

output "kubeconfig_paths" {
  value = {
    manager   = module.rke2_manager.kubeconfig_path
    nprd_apps = module.rke2_apps.kubeconfig_path
  }
}

output "rancher_admin_password" {
  description = "Rancher admin password (from tfvars)"
  value       = "Use the password from rancher_password variable"
  sensitive   = true
}
