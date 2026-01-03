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

variable "ssh_private_key" {
  description = "Path to SSH private key for VM provisioning"
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

variable "rke2_enabled" {
  description = "Enable RKE2 installation via cloud-init"
  type        = bool
  default     = false
}

variable "rke2_version" {
  description = "RKE2 version to install"
  type        = string
  default     = ""
}

variable "rke2_server_token" {
  description = "RKE2 server token for agents to join"
  type        = string
  default     = ""
}

variable "rke2_server_ip" {
  description = "RKE2 server IP for agents to join"
  type        = string
  default     = ""
}

variable "is_rke2_server" {
  description = "Is this the RKE2 server node"
  type        = bool
  default     = false
}
variable "rke2_is_primary" {
  description = "Whether this is a primary/first RKE2 server node in the cluster"
  type        = bool
  default     = false
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
  datastore_id        = "images-import"
  node_name           = var.proxmox_node
  url                 = var.cloud_image_url
  file_name           = "ubuntu-noble-cloudimg-amd64.qcow2"
  overwrite           = true
  overwrite_unmanaged = true
}

# Create VM from cloud image
resource "proxmox_virtual_environment_vm" "vm" {
  vm_id           = var.vm_id
  name            = var.vm_name
  node_name       = var.proxmox_node
  stop_on_destroy = true

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
    type = "nocloud"

    user_account {
      username = "ubuntu"
      # Add SSH public key for ansible/terraform provisioning
      keys = [file("${var.ssh_private_key}.pub")]
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

  # Apply RKE2 installation via cloud-init provisioner if enabled
  provisioner "remote-exec" {
    inline = var.rke2_enabled ? [
      "cat > /tmp/rke2-install.sh <<'RKEEOF'\n${file("${path.module}/cloud-init-rke2.sh")}\nRKEEOF",
      "chmod +x /tmp/rke2-install.sh",
      "IS_RKE2_SERVER=${var.is_rke2_server} RKE2_VERSION=${var.rke2_version} SERVER_IP=${var.rke2_server_ip} SERVER_TOKEN=${var.rke2_server_token} sudo -E bash /tmp/rke2-install.sh"
    ] : ["echo 'RKE2 disabled, skipping installation'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key)
      host        = split("/", var.ip_address)[0]
      timeout     = "30m"
    }
  }

  # Ensure cloud image is downloaded before creating VM
  depends_on = [proxmox_virtual_environment_download_file.ubuntu_cloud_image]
}
