terraform {
  required_version = ">= 1.0"
  required_providers {
    pve = {
      source  = "dataknife/pve"
      version = "1.0.0"
    }
  }
}

provider "pve" {
  endpoint         = var.proxmox_api_url
  api_user         = var.proxmox_api_user
  api_token_id     = var.proxmox_token_id
  api_token_secret = var.proxmox_token_secret
  insecure         = var.proxmox_tls_insecure
}

# Deploy only the nprd-apps cluster
# This cluster is registered to the Rancher manager cluster
resource "pve_qemu" "nprd_apps_nodes" {
  for_each = {
    for i in range(var.node_count) :
    "nprd-apps-${i + 1}" => {
      vm_id       = var.vm_id_base + i
      hostname    = "nprd-apps-${i + 1}"
      ip_octet    = 100 + i
    }
  }

  name     = each.value.hostname
  vmid     = each.value.vm_id
  node     = var.proxmox_node
  clone    = var.vm_template_id

  cores   = var.cpu_cores
  sockets = 1
  memory  = var.memory_mb

  scsi0     = "${var.storage}:${var.disk_size_gb}"
  net0      = "virtio,bridge=vmbr0"
  ciuser    = "ubuntu"
  ipconfig0 = "ip=192.168.14.${each.value.ip_octet}/24,gw=${var.gateway}"
  nameserver = join(" ", var.dns_servers)
  startup   = true
}

output "cluster_ips" {
  description = "NPRD Apps cluster node IP addresses"
  value = {
    for name, vm in pve_qemu.nprd_apps_nodes :
    name => regex("^ip=([0-9.]+)", vm.ipconfig0)[0]
  }
}

output "node_hostnames" {
  description = "NPRD Apps node hostnames"
  value = [
    for vm in pve_qemu.nprd_apps_nodes :
    vm.name
  ]
}
