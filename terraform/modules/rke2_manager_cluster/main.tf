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

variable "cluster_hostname" {
  description = "FQDN for the cluster (e.g., manager.dataknife.net) - used in kubeconfig"
  type        = string
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

variable "dns_servers" {
  description = "DNS servers for CoreDNS forwarding (space-separated)"
  type        = string
  default     = "192.168.1.1 1.1.1.1"
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
      ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_ips[0]} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/${var.cluster_hostname}/' > ~/.kube/${var.cluster_name}.yaml
      chmod 600 ~/.kube/${var.cluster_name}.yaml
      echo "✓ Manager kubeconfig updated with real credentials"
    EOT
  }

  depends_on = [null_resource.wait_for_secondary_servers]
}

# Configure CoreDNS DNS forwarding after cluster is ready
# This ensures external DNS resolution works (e.g., rancher.dataknife.net)
resource "null_resource" "configure_coredns_dns" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "Configuring CoreDNS DNS Forwarding"
      echo "=========================================="
      
      PRIMARY_IP="${var.server_ips[0]}"
      SSH_KEY="${var.ssh_private_key_path}"
      SSH_USER="${var.ssh_user}"
      
      echo "Waiting for CoreDNS to be ready on $PRIMARY_IP..."
      for i in {1..60}; do
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
          'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get deployment -n kube-system rke2-coredns-rke2-coredns &>/dev/null 2>&1'; then
          echo "✓ CoreDNS deployment found at attempt $i"
          break
        fi
        if [ $i -eq 60 ]; then
          echo "⚠ CoreDNS not ready after 120 seconds, but continuing..."
        fi
        sleep 2
      done
      
      echo "Patching CoreDNS ConfigMap with DNS forwarding..."
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" <<'REMOTE_SCRIPT'
        set -e
        export PATH="/var/lib/rancher/rke2/bin:$PATH"
        KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml"
        
        # Patch CoreDNS ConfigMap
        $KUBECTL patch configmap rke2-coredns-rke2-coredns -n kube-system -p '{
          "data": {
            "Corefile": ".:53 {\n    errors\n    health {\n        lameduck 10s\n    }\n    ready\n    kubernetes  cluster.local  cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    prometheus  0.0.0.0:9153\n    forward  . ${var.dns_servers}\n    cache  5\n    loop\n    reload\n    loadbalance\n}\n"
          }
        }' || {
          echo "ERROR: Failed to patch CoreDNS ConfigMap"
          exit 1
        }
        
        # Restart CoreDNS pods
        $KUBECTL rollout restart deployment/rke2-coredns-rke2-coredns -n kube-system || {
          echo "ERROR: Failed to restart CoreDNS"
          exit 1
        }
        
        echo "✓ CoreDNS DNS forwarding configured"
REMOTE_SCRIPT
      
      echo "Waiting for CoreDNS pods to restart..."
      sleep 15
      
      echo "Verifying DNS resolution..."
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" <<'REMOTE_SCRIPT'
        export PATH="/var/lib/rancher/rke2/bin:$PATH"
        KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml"
        
        # Test DNS resolution
        DNS_WORKING=0
        for i in {1..5}; do
          echo "Testing DNS resolution attempt $i..."
          if $KUBECTL run --rm --restart=Never --image=busybox dns-verify-$i -- nslookup rancher.dataknife.net 2>&1 | grep -q "Address:"; then
            echo "✓ DNS resolution successful on attempt $i"
            $KUBECTL delete pod dns-verify-$i --ignore-not-found=true &>/dev/null
            DNS_WORKING=1
            break
          fi
          $KUBECTL delete pod dns-verify-$i --ignore-not-found=true &>/dev/null
          sleep 2
        done
        
        if [ $DNS_WORKING -eq 0 ]; then
          echo "⚠ DNS resolution test failed, but CoreDNS is configured"
          echo "  You can test manually: kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net"
        fi
REMOTE_SCRIPT
      
      echo "=========================================="
      echo "✓ CoreDNS DNS configuration complete"
      echo "=========================================="
    EOT
  }

  depends_on = [null_resource.get_kubeconfig]
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "~/.kube/${var.cluster_name}.yaml"
}

output "api_server_url" {
  description = "Kubernetes API server URL"
  value       = "https://${var.cluster_hostname}:6443"
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}
