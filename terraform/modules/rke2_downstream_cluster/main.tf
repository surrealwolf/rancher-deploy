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

variable "cluster_hostname" {
  description = "FQDN for the cluster (e.g., nprd-apps.dataknife.net) - used in kubeconfig"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for CoreDNS forwarding (space-separated)"
  type        = string
  default     = "192.168.1.1 1.1.1.1"
}

# NOTE: RKE2 is installed via cloud-init during VM provisioning
# This module handles verification and kubeconfig retrieval for downstream clusters

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

# Wait for all nodes to be ready (RKE2 agent or server service running)
# Supports both downstream agent clusters and HA server clusters
resource "null_resource" "wait_for_agent_nodes" {
  count = length(var.agent_ips)

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for RKE2 node at ${var.agent_ips[count.index]}..."
      for i in {1..180}; do
        # Check for either rke2-agent (downstream) or rke2-server (HA cluster)
        if ssh -i ${var.ssh_private_key_path} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${var.ssh_user}@${var.agent_ips[count.index]} 'sudo systemctl is-active --quiet rke2-agent || sudo systemctl is-active --quiet rke2-server' 2>/dev/null; then
          echo "✓ RKE2 node ${var.agent_ips[count.index]} is ready at attempt $i"
          exit 0
        fi
        
        if [ $((i % 30)) -eq 0 ]; then
          echo "  Still waiting for ${var.agent_ips[count.index]}... attempt $i/180"
        fi
        sleep 2
      done
      echo "✗ RKE2 node ${var.agent_ips[count.index]} never became ready"
      exit 1
    EOT
  }

  depends_on = [null_resource.cleanup_known_hosts]
}

# Retrieve kubeconfig from primary downstream node
resource "null_resource" "get_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Retrieving actual kubeconfig from RKE2 downstream server..."
      mkdir -p ~/.kube
      ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.agent_ips[0]} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/${var.cluster_hostname}/' > ~/.kube/${var.cluster_name}.yaml
      chmod 600 ~/.kube/${var.cluster_name}.yaml
      echo "✓ Downstream kubeconfig updated with real credentials"
    EOT
  }

  depends_on = [null_resource.wait_for_agent_nodes]
}

# Configure CoreDNS DNS forwarding after cluster is ready
# This ensures external DNS resolution works (e.g., rancher.dataknife.net)
resource "null_resource" "configure_coredns_dns" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "Configuring CoreDNS DNS Forwarding"
      echo "=========================================="
      
      PRIMARY_IP="${var.agent_ips[0]}"
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

output "api_server_url" {
  description = "Kubernetes API server URL"
  value       = "https://${var.cluster_hostname}:6443"
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}

output "agent_count" {
  description = "Number of agent nodes"
  value       = length(var.agent_ips)
}
