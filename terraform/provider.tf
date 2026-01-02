terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
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

# Enable structured logging to file
# Set TF_LOG=debug or TF_LOG=trace before running terraform apply/plan
# Logs will be written to TF_LOG_PATH if set, otherwise stderr
# Example: export TF_LOG=debug TF_LOG_PATH=terraform.log
# Or configure below for automatic logging

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_user}!${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    agent    = true
    username = "root"
  }
}

# Kubernetes and Helm providers for Rancher deployment
# Only configured when needed via the deploy_rancher flag
# When deploy_rancher = false, these providers won't be used and won't validate kubeconfig existence
provider "kubernetes" {
  config_path = var.deploy_rancher ? pathexpand("~/.kube/rancher-manager.yaml") : ""
}

provider "helm" {
  kubernetes {
    config_path = var.deploy_rancher ? pathexpand("~/.kube/rancher-manager.yaml") : ""
  }
}
