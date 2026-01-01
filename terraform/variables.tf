variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_user" {
  description = "Proxmox API user"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
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
  description = "Proxmox node to create VMs on"
  type        = string
}

variable "clusters" {
  description = "Configuration for Rancher clusters"
  type = map(object({
    name           = string
    node_count     = number
    cpu_cores      = number
    memory_mb      = number
    disk_size_gb   = number
    domain         = string
    ip_subnet      = string
    gateway        = string
    dns_servers    = list(string)
    storage        = string
  }))
}

variable "vm_template_id" {
  description = "Proxmox VM template ID to clone from"
  type        = number
}

variable "rancher_version" {
  description = "Rancher version to install"
  type        = string
  default     = "v2.7.7"
}

variable "rancher_password" {
  description = "Rancher admin password"
  type        = string
  sensitive   = true
}

variable "rancher_hostname" {
  description = "Rancher manager hostname"
  type        = string
}

variable "ssh_private_key" {
  description = "Path to SSH private key for VM access"
  type        = string
  sensitive   = true
}
