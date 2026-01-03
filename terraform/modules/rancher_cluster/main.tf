terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
}

variable "install_rancher" {
  description = "Whether to install Rancher on this cluster"
  type        = bool
  default     = false
}

variable "rancher_version" {
  description = "Rancher version"
  type        = string
}

variable "rancher_password" {
  description = "Rancher admin password"
  type        = string
  sensitive   = true
}

variable "rancher_hostname" {
  description = "Rancher hostname (only for manager cluster)"
  type        = string
  default     = ""
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.13.0"
}

output "kubeconfig_path" {
  value = var.kubeconfig_path
}

output "cluster_name" {
  value = var.cluster_name
}

# Install cert-manager for Rancher (only if deploying Rancher)
resource "helm_release" "cert_manager" {
  count            = var.install_rancher ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_version

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.rancher]
}

# Create rancher namespace (only if deploying Rancher)
resource "kubernetes_namespace" "rancher" {
  count = var.install_rancher ? 1 : 0
  metadata {
    name = "cattle-system"
  }
}

# Install Rancher (only on manager cluster)
resource "helm_release" "rancher" {
  count      = var.install_rancher ? 1 : 0
  name       = "rancher"
  repository = "https://releases.rancher.com/server-charts/stable"
  chart      = "rancher"
  namespace  = kubernetes_namespace.rancher[0].metadata[0].name
  version    = var.rancher_version

  set {
    name  = "hostname"
    value = var.rancher_hostname
  }

  set {
    name  = "replicas"
    value = 3
  }

  set {
    name  = "bootstrapPassword"
    value = var.rancher_password
  }

  set {
    name  = "ingress.tls.source"
    value = "letsEncrypt"
  }

  set {
    name  = "letsEncrypt.email"
    value = "rancher-admin@example.com"
  }

  depends_on = [helm_release.cert_manager]
}

# Create monitoring namespace for agent deployments (only if deploying Rancher)
resource "kubernetes_namespace" "monitoring" {
  count = var.install_rancher ? 1 : 0
  metadata {
    name = "cattle-monitoring-system"
  }
}
