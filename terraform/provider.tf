terraform {
  required_version = ">= 1.0"
  required_providers {
    pve = {
      source  = "dataknife/pve"
      version = "1.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "pve" {
  endpoint         = var.proxmox_api_url
  api_user         = var.proxmox_api_user
  api_token_id     = var.proxmox_api_token_id
  api_token_secret = var.proxmox_api_token_secret
  insecure         = var.proxmox_tls_insecure
}
