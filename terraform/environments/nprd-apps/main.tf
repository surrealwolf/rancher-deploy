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

# Deploy only the nprd-apps cluster
# This cluster is registered to the Rancher manager cluster
resource "proxmox_vm_qemu" "nprd_apps_nodes" {
  for_each = {
    for i in range(var.node_count) :
    "nprd-apps-${i + 1}" => {
      vm_id       = 200 + i
      hostname    = "nprd-apps-${i + 1}"
      ip_octet    = 100 + i
    }
  }

  name        = each.value.hostname
  vmid        = each.value.vm_id
  target_node = var.proxmox_node
  clone       = "ubuntu-${var.vm_template_id}"

  cores   = var.cpu_cores
  sockets = 1
  memory  = var.memory_mb

  disk {
    type    = "virtio"
    storage = var.storage
    size    = "${var.disk_size_gb}G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser = "ubuntu"

  ipconfig0 = "ip=192.168.2.${each.value.ip_octet}/24,gw=${var.gateway}"
  nameserver = join(" ", var.dns_servers)

  additional_wait_for_cloudinit_seconds = 30

  provisioner "remote-exec" {
    inline = [
      "echo 'NPRD Apps node is ready'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key)
      host        = "192.168.2.${each.value.ip_octet}"
      timeout     = "5m"
    }
  }
}

output "cluster_ips" {
  description = "NPRD Apps cluster node IP addresses"
  value = {
    for key, vm in proxmox_vm_qemu.nprd_apps_nodes :
    vm.name => "192.168.2.${key}"
  }
}

output "node_hostnames" {
  description = "NPRD Apps node hostnames"
  value = [
    for vm in proxmox_vm_qemu.nprd_apps_nodes :
    vm.name
  ]
}
