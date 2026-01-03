terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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
# Uses local-exec with helm CLI to handle self-signed certificates
resource "null_resource" "install_cert_manager" {
  count = var.install_rancher ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing cert-manager..."
      export KUBECONFIG="${var.kubeconfig_path}"
      
      # Add Jetstack helm repo
      helm repo add jetstack https://charts.jetstack.io --force-update || true
      helm repo update
      
      # Create namespace
      kubectl create namespace cert-manager --insecure-skip-tls-verify 2>/dev/null || true
      
      # Install cert-manager with self-signed cert support
      helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --insecure-skip-tls-verify \
        --set installCRDs=true \
        --version ${var.cert_manager_version} \
        --wait \
        --timeout 10m
      
      echo "✓ cert-manager installed"
    EOT
    
    environment = {
      KUBECONFIG = pathexpand(var.kubeconfig_path)
    }
  }
}

# Install Rancher (only on manager cluster)
# Uses local-exec with helm CLI to handle self-signed certificates
resource "null_resource" "install_rancher" {
  count = var.install_rancher ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing Rancher..."
      export KUBECONFIG="${var.kubeconfig_path}"
      
      # Add Rancher helm repo
      helm repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update || true
      helm repo update
      
      # Create namespace
      kubectl create namespace cattle-system --insecure-skip-tls-verify 2>/dev/null || true
      
      # Install Rancher with self-signed cert support
      helm install rancher rancher-stable/rancher \
        --namespace cattle-system \
        --insecure-skip-tls-verify \
        --set hostname=${var.rancher_hostname} \
        --set replicas=3 \
        --set bootstrapPassword=${var.rancher_password} \
        --version ${var.rancher_version} \
        --wait \
        --timeout 15m
      
      echo "✓ Rancher installed at https://${var.rancher_hostname}"
      
      # Get bootstrap secret
      sleep 10
      BOOTSTRAP_PWD=$(kubectl get secret --namespace cattle-system bootstrap-secret \
        -o go-template='{{.data.bootstrapPassword|base64decode}}' \
        --insecure-skip-tls-verify 2>/dev/null || echo "check manually")
      echo ""
      echo "Rancher bootstrap password: $BOOTSTRAP_PWD"
    EOT
    
    environment = {
      KUBECONFIG = pathexpand(var.kubeconfig_path)
    }
  }

  depends_on = [null_resource.install_cert_manager]
}

# Optional: Create monitoring namespace for future agent deployments
resource "null_resource" "create_monitoring_namespace" {
  count = var.install_rancher ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${var.kubeconfig_path}"
      kubectl create namespace cattle-monitoring-system --insecure-skip-tls-verify 2>/dev/null || true
      echo "✓ Monitoring namespace ready"
    EOT
    
    environment = {
      KUBECONFIG = pathexpand(var.kubeconfig_path)
    }
  }

  depends_on = [null_resource.install_rancher]
}
