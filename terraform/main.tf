module "rancher_manager" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(var.clusters["manager"].node_count) :
    "manager-${i + 1}" => {
      vm_id       = 401 + i
      hostname    = "rancher-manager-${i + 1}"
      ip_address  = "192.168.1.${100 + i}/24"
    }
  }

  vm_name      = each.value.hostname
  vm_id        = each.value.vm_id
  template_id  = var.vm_template_id
  proxmox_node = var.proxmox_node
  
  cpu_cores    = var.clusters["manager"].cpu_cores
  memory_mb    = var.clusters["manager"].memory_mb
  disk_size_gb = var.clusters["manager"].disk_size_gb
  storage      = var.clusters["manager"].storage
  
  hostname     = each.value.hostname
  ip_address   = each.value.ip_address
  gateway      = var.clusters["manager"].gateway
  dns_servers  = var.clusters["manager"].dns_servers
  domain       = var.clusters["manager"].domain
  
  ssh_private_key = var.ssh_private_key
}

module "nprd_apps" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(var.clusters["nprd-apps"].node_count) :
    "nprd-apps-${i + 1}" => {
      vm_id       = 404 + i
      hostname    = "nprd-apps-${i + 1}"
      ip_address  = "192.168.2.${100 + i}/24"
    }
  }

  vm_name      = each.value.hostname
  vm_id        = each.value.vm_id
  template_id  = var.vm_template_id
  proxmox_node = var.proxmox_node
  
  cpu_cores    = var.clusters["nprd-apps"].cpu_cores
  memory_mb    = var.clusters["nprd-apps"].memory_mb
  disk_size_gb = var.clusters["nprd-apps"].disk_size_gb
  storage      = var.clusters["nprd-apps"].storage
  
  hostname     = each.value.hostname
  ip_address   = each.value.ip_address
  gateway      = var.clusters["nprd-apps"].gateway
  dns_servers  = var.clusters["nprd-apps"].dns_servers
  domain       = var.clusters["nprd-apps"].domain
  
  ssh_private_key = var.ssh_private_key
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

output "kubeconfig_path" {
  value = {
    manager   = pathexpand("~/.kube/rancher-manager-config")
    nprd_apps = pathexpand("~/.kube/nprd-apps-config")
  }
}
