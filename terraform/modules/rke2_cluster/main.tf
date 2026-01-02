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
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = "ubuntu"
}

variable "rke2_version" {
  description = "RKE2 version"
  type        = string
  default     = "v1.34.3+rke2r1"
}

# Clean up SSH known_hosts for all IPs to prevent host key warnings
resource "null_resource" "cleanup_known_hosts" {
  provisioner "local-exec" {
    command = <<-EOT
      for ip in ${join(" ", concat(var.server_ips, var.agent_ips))}; do
        ssh-keygen -R "$ip" 2>/dev/null || true
      done
      echo "Cleaned up SSH known_hosts for all cluster IPs"
    EOT
  }
}

# Wait for cloud-init to complete before installing RKE2
resource "null_resource" "wait_for_cloud_init" {
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Cloud-init still running...'; sleep 5; done",
      "echo 'Cloud-init completed'",
      "cloud-init status --wait",
      "echo 'Ready for RKE2 installation'",
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = var.server_ips[0]
      timeout     = "10m"
    }
  }

  depends_on = [null_resource.cleanup_known_hosts]
}

# Install RKE2 on first server node
resource "null_resource" "rke2_server_init" {
  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh",
      "chmod +x /tmp/rke2-install.sh",
      "sudo -E bash -c 'INSTALL_RKE2_VERSION=${var.rke2_version} /tmp/rke2-install.sh'",
      "sudo systemctl enable --now rke2-server",
      "sleep 30", # Wait for RKE2 to start
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = var.server_ips[0]
      timeout     = "10m"
    }
  }

  depends_on = [null_resource.wait_for_cloud_init]
}

# Wait for SSH to be available on first server node
resource "null_resource" "wait_for_ssh" {
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..60}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'echo ready' 2>/dev/null; then
          echo "SSH is ready"
          exit 0
        fi
        echo "Waiting for SSH... attempt $i/60"
        sleep 2
      done
      echo "SSH never became available"
      exit 1
    EOT
  }

  depends_on = [null_resource.rke2_server_init]
}

# Wait for RKE2 server to be ready (not just SSH)
resource "null_resource" "wait_for_rke2" {
  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..120}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /var/lib/rancher/rke2/server/node-token' 2>/dev/null; then
          echo "RKE2 server is ready with token file"
          exit 0
        fi
        echo "Waiting for RKE2 server... attempt $i/120"
        sleep 2
      done
      echo "RKE2 server never became ready"
      exit 1
    EOT
  }

  depends_on = [null_resource.wait_for_ssh]
}

# Get server token for joining other nodes
resource "null_resource" "get_server_token" {
  provisioner "local-exec" {
    command = "ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /var/lib/rancher/rke2/server/node-token' > /tmp/${var.cluster_name}_token.txt"
  }

  depends_on = [null_resource.wait_for_rke2]
}

# Join additional server nodes
resource "null_resource" "wait_for_server_ssh" {
  count = length(var.server_ips) > 1 ? length(var.server_ips) - 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..60}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[count.index + 1]} 'echo ready' 2>/dev/null; then
          echo "SSH is ready on ${var.server_ips[count.index + 1]}"
          exit 0
        fi
        echo "Waiting for SSH on ${var.server_ips[count.index + 1]}... attempt $i/60"
        sleep 2
      done
      echo "SSH never became available on ${var.server_ips[count.index + 1]}"
      exit 1
    EOT
  }

  depends_on = [null_resource.get_server_token]
}

resource "null_resource" "rke2_server_join" {
  count = length(var.server_ips) > 1 ? length(var.server_ips) - 1 : 0

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh",
      "chmod +x /tmp/rke2-install.sh",
      "sudo -E bash -c 'INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_TYPE=server /tmp/rke2-install.sh'",
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

  depends_on = [null_resource.wait_for_server_ssh]
}

# Join agent nodes (if provided)
resource "null_resource" "wait_for_agent_ssh" {
  count = length(var.agent_ips)

  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..60}; do
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.agent_ips[count.index]} 'echo ready' 2>/dev/null; then
          echo "SSH is ready on ${var.agent_ips[count.index]}"
          exit 0
        fi
        echo "Waiting for SSH on ${var.agent_ips[count.index]}... attempt $i/60"
        sleep 2
      done
      echo "SSH never became available on ${var.agent_ips[count.index]}"
      exit 1
    EOT
  }

  depends_on = [null_resource.get_server_token]
}

resource "null_resource" "rke2_agent_join" {
  count = length(var.agent_ips)

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh",
      "chmod +x /tmp/rke2-install.sh",
      "sudo -E bash -c 'INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_TYPE=agent /tmp/rke2-install.sh'",
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

  depends_on = [null_resource.wait_for_agent_ssh]
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
