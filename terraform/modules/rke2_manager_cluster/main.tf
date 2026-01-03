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

variable "server_ips" {
  description = "List of manager server node IPs"
  type        = list(string)
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = "ubuntu"
}

# NOTE: RKE2 is installed via cloud-init during VM provisioning
# This module handles cluster verification and kubeconfig retrieval for manager clusters

# Clean up SSH known_hosts for all manager IPs
resource "null_resource" "cleanup_known_hosts" {
  provisioner "local-exec" {
    command = <<-EOT
      for ip in ${join(" ", var.server_ips)}; do
        ssh-keygen -R "$ip" 2>/dev/null || true
      done
      echo "✓ Cleaned up SSH known_hosts for manager cluster"
    EOT
  }
}

# Wait for primary RKE2 server to be ready (token file exists)
# Primary server starts standalone and generates the cluster token
resource "null_resource" "wait_for_primary_server" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for primary RKE2 manager server at ${var.server_ips[0]}..."
      for i in {1..180}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo test -f /var/lib/rancher/rke2/server/node-token' 2>/dev/null; then
          echo "✓ Primary RKE2 manager server is ready at attempt $i"
          exit 0
        fi
        
        if [ $((i % 30)) -eq 0 ]; then
          echo "  Still waiting... attempt $i/180 (at $((i * 2)) seconds)"
        fi
        sleep 2
      done
      echo "✗ Primary RKE2 server never became ready after 6 minutes"
      exit 1
    EOT
  }

  depends_on = [null_resource.cleanup_known_hosts]
}

# Wait for secondary manager servers to join the HA cluster
# Secondary servers fetch the token from primary and join as control-plane nodes
resource "null_resource" "wait_for_secondary_servers" {
  count = length(var.server_ips) > 1 ? length(var.server_ips) - 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for secondary RKE2 manager server at ${var.server_ips[count.index + 1]} to join cluster..."
      for i in {1..180}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[count.index + 1]} 'sudo systemctl is-active --quiet rke2-server' 2>/dev/null; then
          echo "✓ Secondary manager server ${var.server_ips[count.index + 1]} is active"
          exit 0
        fi
        
        if [ $((i % 30)) -eq 0 ]; then
          echo "  Still waiting for ${var.server_ips[count.index + 1]}... attempt $i/180"
        fi
        sleep 2
      done
      echo "✗ Secondary manager server ${var.server_ips[count.index + 1]} never became ready"
      exit 1
    EOT
  }

  depends_on = [null_resource.wait_for_primary_server]
}

# Retrieve REAL kubeconfig from primary manager server
# (Overwrites the placeholder kubeconfig created during cloud-init)
resource "null_resource" "get_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Retrieving actual kubeconfig from RKE2 primary server..."
      mkdir -p ~/.kube
      ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/${var.server_ips[0]}/' > ~/.kube/${var.cluster_name}.yaml
      chmod 600 ~/.kube/${var.cluster_name}.yaml
      echo "✓ Manager kubeconfig updated with real credentials"
    EOT
  }

  depends_on = [null_resource.wait_for_secondary_servers]
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "~/.kube/${var.cluster_name}.yaml"
}

output "api_server_url" {
  description = "Kubernetes API server URL"
  value       = "https://${var.server_ips[0]}:6443"
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}
