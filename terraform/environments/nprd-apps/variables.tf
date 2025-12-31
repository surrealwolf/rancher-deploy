variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Disable TLS verification for Proxmox API"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_template_id" {
  description = "VM template ID"
  type        = number
}

variable "ssh_private_key" {
  description = "Path to SSH private key"
  type        = string
  sensitive   = true
}

variable "node_count" {
  description = "Number of nodes in nprd-apps cluster"
  type        = number
  default     = 3
}

variable "cpu_cores" {
  description = "CPU cores per node"
  type        = number
  default     = 8
}

variable "memory_mb" {
  description = "Memory in MB per node"
  type        = number
  default     = 16384
}

variable "disk_size_gb" {
  description = "Disk size in GB per node"
  type        = number
  default     = 150
}

variable "gateway" {
  description = "Gateway IP"
  type        = string
  default     = "192.168.1.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "storage" {
  description = "Storage target"
  type        = string
  default     = "local-lvm"
}
