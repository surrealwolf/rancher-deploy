terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

variable "vm_name" {
  description = "VM name"
  type        = string
}

variable "vm_id" {
  description = "VM ID"
  type        = number
}

variable "template_id" {
  description = "Template VM ID to clone from"
  type        = number
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
}

variable "storage" {
  description = "Storage target"
  type        = string
}

variable "hostname" {
  description = "Hostname"
  type        = string
}

variable "ip_address" {
  description = "IP address with CIDR"
  type        = string
}

variable "gateway" {
  description = "Gateway IP"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
}

variable "domain" {
  description = "Domain name"
  type        = string
}

output "vm_id" {
  value = proxmox_vm_qemu.vm.vmid
}

output "ip_address" {
  value = var.ip_address
}

output "hostname" {
  value = var.hostname
}

resource "proxmox_vm_qemu" "vm" {
  name        = var.vm_name
  vmid        = var.vm_id
  target_node = var.proxmox_node
  clone       = "ubuntu-${var.template_id}"

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
  
  ipconfig0 = "ip=${var.ip_address},gw=${var.gateway}"
  nameserver = join(" ", var.dns_servers)

  additional_wait_for_cloudinit_seconds = 30

  provisioner "remote-exec" {
    inline = [
      "echo 'VM is ready'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key)
      host        = split("/", var.ip_address)[0]
      timeout     = "5m"
    }
  }
}
