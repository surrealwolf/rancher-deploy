terraform {
  required_providers {
    pve = {
      source  = "dataknife/pve"
      version = "1.0.0"
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

variable "vlan_id" {
  description = "VLAN ID for network interface"
  type        = number
  default     = 0
}

output "vm_id" {
  value = pve_qemu.vm.vmid
}

output "ip_address" {
  value = var.ip_address
}

output "hostname" {
  value = var.hostname
}

resource "pve_qemu" "vm" {
  vmid      = var.vm_id
  name      = var.vm_name
  node      = var.proxmox_node
  clone     = var.template_id
  cores     = var.cpu_cores
  sockets   = 1
  memory    = var.memory_mb
  net0      = "virtio,bridge=vmbr0,tag=${var.vlan_id > 0 ? var.vlan_id : 0}"
  scsi0     = "${var.storage}:${var.disk_size_gb}"
  ciuser    = "ubuntu"
  ipconfig0 = "ip=${var.ip_address},gw=${var.gateway}"
  nameserver = join(" ", var.dns_servers)
}
