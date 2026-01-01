terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
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

variable "cloud_image_url" {
  description = "Ubuntu cloud image URL"
  type        = string
}

variable "datastore_id" {
  description = "Datastore ID for storing cloud image"
  type        = string
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
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "ip_address" {
  value = var.ip_address
}

output "hostname" {
  value = var.hostname
}

# Download Ubuntu cloud image to dedicated import storage
# This storage was created specifically to support 'import' content type
# The image is then imported into the VM datastore via the disk block's import_from parameter
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type        = "import"
  datastore_id        = "images-import"  # File-based storage configured for cloud image imports
  node_name           = var.proxmox_node
  url                 = var.cloud_image_url
  file_name           = "ubuntu-noble-cloudimg-amd64.qcow2"  # Same filename for all VMs (shared image)
  overwrite           = true
  overwrite_unmanaged = true
}

# Create VM from cloud image
resource "proxmox_virtual_environment_vm" "vm" {
  vm_id             = var.vm_id
  name              = var.vm_name
  node_name         = var.proxmox_node
  stop_on_destroy   = true

  cpu {
    cores   = var.cpu_cores
    sockets = 1
  }

  memory {
    dedicated = var.memory_mb
  }

  # Import cloud image as primary disk and expand
  disk {
    datastore_id = var.datastore_id
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_gb
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = var.vlan_id > 0 ? var.vlan_id : null
  }

  initialization {
    user_account {
      username = "ubuntu"
    }

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  # Ensure cloud image is downloaded before creating VM
  depends_on = [proxmox_virtual_environment_download_file.ubuntu_cloud_image]
}
