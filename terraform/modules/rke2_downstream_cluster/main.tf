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

variable "agent_ips" {
  description = "List of agent node IPs"
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
# This module handles verification of downstream/agent clusters only
# (no kubeconfig retrieval since agents don't host the API server)

# Clean up SSH known_hosts for all agent IPs
resource "null_resource" "cleanup_known_hosts" {
  provisioner "local-exec" {
    command = <<-EOT
      for ip in ${join(" ", var.agent_ips)}; do
        ssh-keygen -R "$ip" 2>/dev/null || true
      done
      echo "✓ Cleaned up SSH known_hosts for downstream agent cluster"
    EOT
  }
}

# Wait for all agent nodes to be ready (RKE2 agent service running)
# Agents join an external control plane (specified via RKE2_URL env var in cloud-init)
resource "null_resource" "wait_for_agent_nodes" {
  count = length(var.agent_ips)

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for RKE2 agent node at ${var.agent_ips[count.index]}..."
      for i in {1..180}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.agent_ips[count.index]} 'sudo systemctl is-active --quiet rke2-agent' 2>/dev/null; then
          echo "✓ Agent node ${var.agent_ips[count.index]} is ready at attempt $i"
          exit 0
        fi
        
        if [ $((i % 30)) -eq 0 ]; then
          echo "  Still waiting for ${var.agent_ips[count.index]}... attempt $i/180"
        fi
        sleep 2
      done
      echo "✗ Agent node ${var.agent_ips[count.index]} never became ready"
      exit 1
    EOT
  }

  depends_on = [null_resource.cleanup_known_hosts]
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}

output "agent_count" {
  description = "Number of agent nodes"
  value       = length(var.agent_ips)
}
