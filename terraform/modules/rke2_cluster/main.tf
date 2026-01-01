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
  description = "List of server node IPs"
  type        = list(string)
}

variable "agent_ips" {
  description = "List of agent node IPs (optional)"
  type        = list(string)
  default     = []
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = "ubuntu"
}

variable "rke2_version" {
  description = "RKE2 version"
  type        = string
  default     = "latest"
}

# Install RKE2 on first server node
resource "null_resource" "rke2_server_init" {
  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${var.rke2_version} sh -",
      "sudo systemctl enable --now rke2-server",
      "sleep 30", # Wait for RKE2 to start
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = var.server_ips[0]
      timeout     = "5m"
    }
  }

  depends_on = []
}

# Get server token for joining other nodes
resource "null_resource" "get_server_token" {
  provisioner "local-exec" {
    command = "ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /var/lib/rancher/rke2/server/node-token' > /tmp/${var.cluster_name}_token.txt"
  }

  depends_on = [null_resource.rke2_server_init]
}

# Join additional server nodes
resource "null_resource" "rke2_server_join" {
  count = length(var.server_ips) > 1 ? length(var.server_ips) - 1 : 0

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_TYPE=server sh -",
      "sudo mkdir -p /etc/rancher/rke2",
      "sudo tee /etc/rancher/rke2/config.yaml > /dev/null << EOF\nserver: https://${var.server_ips[0]}:6443\ntoken: $(cat /tmp/${var.cluster_name}_token.txt)\nEOF",
      "sudo systemctl enable --now rke2-server",
      "sleep 30",
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = var.server_ips[count.index + 1]
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.get_server_token]
}

# Join agent nodes (if provided)
resource "null_resource" "rke2_agent_join" {
  count = length(var.agent_ips)

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_TYPE=agent sh -",
      "sudo mkdir -p /etc/rancher/rke2",
      "sudo tee /etc/rancher/rke2/config.yaml > /dev/null << EOF\nserver: https://${var.server_ips[0]}:6443\ntoken: $(cat /tmp/${var.cluster_name}_token.txt)\nEOF",
      "sudo systemctl enable --now rke2-agent",
      "sleep 30",
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = var.agent_ips[count.index]
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.get_server_token]
}

# Retrieve kubeconfig from first server
resource "null_resource" "get_kubeconfig" {
  provisioner "local-exec" {
    command = "mkdir -p ~/.kube && ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/${var.server_ips[0]}/' > ~/.kube/${var.cluster_name}.yaml"
  }

  depends_on = [null_resource.rke2_server_init]
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
