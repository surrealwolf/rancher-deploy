terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

variable "rancher_url" {
  description = "Rancher manager URL"
  type        = string
}

variable "rancher_token_file" {
  description = "Path to Rancher API token file"
  type        = string
}

variable "cluster_id" {
  description = "Downstream cluster ID (e.g., c-abc123)"
  type        = string
}

variable "cluster_nodes" {
  description = "Map of node names to IP addresses"
  type        = map(string)
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for accessing nodes"
  type        = string
  default     = "ubuntu"
}

variable "install_script_path" {
  description = "Path to install-system-agent.sh script"
  type        = string
  default     = ""
}

# Install system-agent on all downstream cluster nodes
resource "null_resource" "install_system_agent" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "=============================================="
      echo "Installing Rancher System-Agent on Nodes"
      echo "=============================================="
      
      RANCHER_URL="${var.rancher_url}"
      RANCHER_TOKEN=$(cat "${var.rancher_token_file}")
      CLUSTER_ID="${var.cluster_id}"
      SSH_KEY="${var.ssh_private_key_path}"
      SSH_USER="${var.ssh_user}"
      
      # Fetch registration token
      echo "[1/3] Fetching registration token from Rancher..."
      TOKEN_ID=$(curl -sk \
        -H "Authorization: Bearer $RANCHER_TOKEN" \
        "$RANCHER_URL/v3/clusters/$CLUSTER_ID/clusterregistrationtokens" 2>/dev/null | \
        jq -r '.data[0].token // empty')
      
      if [ -z "$TOKEN_ID" ]; then
        echo "ERROR: Failed to get registration token"
        exit 1
      fi
      echo "  ✓ Token: $TOKEN_ID"
      
      # Download and apply manifest on each node
      echo "[2/3] Downloading system-agent manifest..."
      MANIFEST=$(curl -sk \
        -H "Authorization: Bearer $RANCHER_TOKEN" \
        "$RANCHER_URL/v3/import/$${TOKEN_ID}.yaml" 2>/dev/null)
      
      if [ -z "$MANIFEST" ]; then
        echo "ERROR: Failed to download manifest"
        exit 1
      fi
      echo "  ✓ Manifest downloaded"
      
      # Apply manifest on each node
      echo "[3/3] Installing system-agent on cluster nodes..."
      
      %{ for node_name, node_ip in var.cluster_nodes ~}
      echo "  Installing on ${node_name} (${node_ip})..."
      ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@${node_ip}" << EOSSH
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
echo "$MANIFEST" | sudo /var/lib/rancher/rke2/bin/kubectl apply -f -
EOSSH
      echo "  ✓ Applied to ${node_name}"
      %{ endfor ~}
      
      echo ""
      echo "=============================================="
      echo "✓ System-Agent Installation Complete!"
      echo "=============================================="
      echo ""
      echo "Nodes should now appear in Rancher Manager:"
      echo "  $RANCHER_URL/dashboard/c/$CLUSTER_ID"
      echo ""
      echo "Monitor pod status:"
      for node_ip in ${join(" ", values(var.cluster_nodes))}; do
        echo "  ssh ubuntu@$node_ip 'sudo /var/lib/rancher/rke2/bin/kubectl get -A pods -l app=rancher-system-agent'"
      done
    EOT
  }
}
