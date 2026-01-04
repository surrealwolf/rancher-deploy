terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
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

variable "kubeconfig_path" {
  description = "Path to downstream cluster kubeconfig"
  type        = string
}

# Register downstream cluster using manifest-based approach
# This fetches the registration manifest from Rancher and applies it directly
resource "null_resource" "register_downstream_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "=============================================="
      echo "Registering Downstream Cluster with Rancher"
      echo "=============================================="
      
      RANCHER_URL="${var.rancher_url}"
      API_TOKEN=$(cat "${var.rancher_token_file}")
      CLUSTER_ID="${var.cluster_id}"
      SSH_KEY="${var.ssh_private_key_path}"
      SSH_USER="${var.ssh_user}"
      
      # Step 1: Get or create registration token
      echo "[1/3] Fetching registration token from Rancher..."
      
      TOKEN_RESPONSE=$(curl -sk \
        -H "Authorization: Bearer $API_TOKEN" \
        "$RANCHER_URL/v3/clusters/$CLUSTER_ID/clusterregistrationtokens" 2>/dev/null)
      
      TOKEN_COUNT=$(echo "$TOKEN_RESPONSE" | jq '.data | length')
      
      if [ "$TOKEN_COUNT" -eq 0 ]; then
        echo "  Creating new registration token..."
        TOKEN_RESPONSE=$(curl -sk -X POST \
          -H "Authorization: Bearer $API_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"type\": \"clusterregistrationtoken\", \"clusterId\": \"$CLUSTER_ID\"}" \
          "$RANCHER_URL/v3/clusterregistrationtokens" 2>/dev/null)
      fi
      
      # Get the token ID and value
      TOKEN_ID=$(echo "$TOKEN_RESPONSE" | jq -r '.id // .data[0].id // empty')
      TOKEN_VALUE=$(echo "$TOKEN_RESPONSE" | jq -r '.token // .data[0].token // empty')
      
      if [ -z "$TOKEN_ID" ] || [ -z "$TOKEN_VALUE" ]; then
        echo "ERROR: Failed to get or create registration token"
        echo "$TOKEN_RESPONSE" | jq '.'
        exit 1
      fi
      
      echo "  ✓ Token: $TOKEN_ID"
      
      # Step 2: Fetch cluster registration manifest
      echo "[2/3] Fetching cluster registration manifest from Rancher..."
      
      # Note: Using double dollar signs to escape Terraform interpolation for shell variables
      MANIFEST_URL="$RANCHER_URL/v3/import/$${TOKEN_VALUE}_$${CLUSTER_ID}.yaml"
      
      # Download and apply manifest to each node
      echo "[3/3] Applying registration manifest to cluster nodes..."
      
      %{ for node_name, node_ip in var.cluster_nodes ~}
      echo "  Registering ${node_name} (${node_ip})..."
      
      # Apply manifest to the node using kubectl
      if ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@${node_ip}" \
        "curl -sk $MANIFEST_URL | sudo /var/lib/rancher/rke2/bin/kubectl apply -f -" 2>&1 | grep -q "created\|unchanged"; then
        echo "  ✓ Registered ${node_name}"
      else
        echo "  ⚠ Registration on ${node_name} may have failed"
      fi
      %{ endfor ~}
      
      echo ""
      echo "=============================================="
      echo "✓ Cluster Registration Complete!"
      echo "=============================================="
      echo ""
      echo "Manifest URL: $MANIFEST_URL"
      echo ""
      echo "Monitor cattle-cluster-agent pods:"
      echo "  kubectl -n cattle-system get pods -l app=cattle-cluster-agent"
      echo ""
      echo "Cluster should now appear in Rancher Manager:"
      echo "  $RANCHER_URL/dashboard/c/$CLUSTER_ID"
    EOT
  }
}
