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
      
      # Fetch registration token info
      echo "[1/3] Fetching registration token from Rancher..."
      TOKEN_RESPONSE=$(curl -sk \
        -H "Authorization: Bearer $RANCHER_TOKEN" \
        "$RANCHER_URL/v3/clusters/$CLUSTER_ID/clusterregistrationtokens" 2>/dev/null)
      
      # Check if token exists, if not create one
      TOKEN_COUNT=$(echo "$TOKEN_RESPONSE" | jq '.data | length')
      
      if [ "$TOKEN_COUNT" -eq 0 ]; then
        echo "  Creating new registration token..."
        TOKEN_RESPONSE=$(curl -sk -X POST \
          -H "Authorization: Bearer $RANCHER_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"type\": \"clusterregistrationtoken\", \"clusterId\": \"$CLUSTER_ID\"}" \
          "$RANCHER_URL/v3/clusterregistrationtokens" 2>/dev/null)
      fi
      
      # Get the full token ID (format: clusterid:tokenid)
      TOKEN_FULL=$(echo "$TOKEN_RESPONSE" | jq -r '.id // .data[0].id // empty')
      
      if [ -z "$TOKEN_FULL" ]; then
        echo "ERROR: Failed to get or create registration token"
        echo "$TOKEN_RESPONSE" | jq '.'
        exit 1
      fi
      echo "  ✓ Token: $TOKEN_FULL"
      
      # Get system-agent installation command from Rancher API
      echo "[2/3] Fetching system-agent installation command..."
      
      # Extract nodeCommand - works with both GET list response and POST single response
      NODE_COMMAND=$(echo "$TOKEN_RESPONSE" | jq -r ".nodeCommand // .data[0].nodeCommand // empty" | head -1)
      
      if [ -z "$NODE_COMMAND" ]; then
        echo "ERROR: Could not get system-agent installation command"
        echo "API Response:"
        echo "$TOKEN_RESPONSE" | jq '.'
        exit 0
      fi
      
      # Add cluster roles (etcd, controlplane, worker) for full node registration
      NODE_COMMAND="$NODE_COMMAND --etcd --controlplane --worker"
      
      # Use insecure variant (skip cert verification) for self-signed certs
      NODE_COMMAND=$(echo "$NODE_COMMAND" | sed 's|curl -fL|curl --insecure -fL|g')
      
      echo "  ✓ Installation command retrieved"
      
      # Install system-agent on each node
      echo "[3/3] Installing system-agent on cluster nodes..."
      
      %{ for node_name, node_ip in var.cluster_nodes ~}
      echo "  Installing on ${node_name} (${node_ip})..."
      
      # Run the installation command on the node
      if ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@${node_ip}" "bash -c '$NODE_COMMAND'" 2>/dev/null; then
        echo "  ✓ Installed on ${node_name}"
      else
        echo "  ⚠ Installation on ${node_name} failed or already installed"
      fi
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
