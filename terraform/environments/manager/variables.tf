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

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "lab.local"
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

variable "rancher_version" {
  description = "Rancher version"
  type        = string
  default     = "v2.7.7"
}

variable "rancher_password" {
  description = "Rancher bootstrap password"
  type        = string
  sensitive   = true
}

variable "rancher_hostname" {
  description = "Rancher hostname"
  type        = string
}
