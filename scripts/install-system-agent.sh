#!/bin/bash

# Script to install Rancher system-agent on downstream cluster nodes
# This completes the registration process after terraform apply
#
# Usage:
#   ./install-system-agent.sh \
#     --rancher-url https://rancher.example.com \
#     --rancher-token token-xxxxx:yyyyyy \
#     --cluster-id c-abc123 \
#     --nodes 192.168.14.110 192.168.14.111 192.168.14.112 \
#     --ssh-key ~/.ssh/id_rsa
#

set -e

# Default values
RANCHER_URL=""
RANCHER_TOKEN=""
CLUSTER_ID=""
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_USER="ubuntu"
NODES=()
DRY_RUN=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $@"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $@"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $@" >&2
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --rancher-url)
        RANCHER_URL="$2"
        shift 2
        ;;
      --rancher-token)
        RANCHER_TOKEN="$2"
        shift 2
        ;;
      --cluster-id)
        CLUSTER_ID="$2"
        shift 2
        ;;
      --nodes)
        shift
        while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
          NODES+=("$1")
          shift
        done
        ;;
      --ssh-key)
        SSH_KEY="$2"
        shift 2
        ;;
      --ssh-user)
        SSH_USER="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

print_usage() {
  cat << EOF
Usage: $(basename $0) [OPTIONS]

Options:
  --rancher-url URL           Rancher manager URL (e.g., https://rancher.example.com)
  --rancher-token TOKEN       Rancher API token (e.g., token-xxxxx:yyyyyy)
  --cluster-id ID             Downstream cluster ID (e.g., c-abc123)
  --nodes IPS                 Space-separated list of node IPs
  --ssh-key PATH              Path to SSH private key (default: ~/.ssh/id_rsa)
  --ssh-user USER             SSH user (default: ubuntu)
  --dry-run                   Show what would be done without executing

Example:
  $(basename $0) \\
    --rancher-url https://rancher.dataknife.net \\
    --rancher-token token-rgj6b:c464... \\
    --cluster-id c-7c2vb \\
    --nodes 192.168.14.110 192.168.14.111 192.168.14.112
EOF
}

# Validate inputs
validate_inputs() {
  if [[ -z "$RANCHER_URL" ]]; then
    log_error "Missing --rancher-url"
    print_usage
    exit 1
  fi

  if [[ -z "$RANCHER_TOKEN" ]]; then
    log_error "Missing --rancher-token"
    print_usage
    exit 1
  fi

  if [[ -z "$CLUSTER_ID" ]]; then
    log_error "Missing --cluster-id"
    print_usage
    exit 1
  fi

  if [[ ${#NODES[@]} -eq 0 ]]; then
    log_error "Missing --nodes"
    print_usage
    exit 1
  fi

  if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
  fi
}

# Get registration token for cluster
get_registration_token() {
  log_info "Fetching registration token for cluster $CLUSTER_ID..."
  
  TOKENS=$(curl -sk \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    "$RANCHER_URL/v3/clusters/$CLUSTER_ID/clusterregistrationtokens" 2>/dev/null)
  
  # Extract the first token's name
  TOKEN_ID=$(echo "$TOKENS" | jq -r '.data[0].name' 2>/dev/null)
  
  if [[ -z "$TOKEN_ID" ]] || [[ "$TOKEN_ID" == "null" ]]; then
    log_error "Failed to get registration token"
    log_info "Creating new registration token..."
    
    # Create new token
    TOKEN_RESPONSE=$(curl -sk -X POST \
      -H "Authorization: Bearer $RANCHER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"type":"clusterRegistrationToken"}' \
      "$RANCHER_URL/v3/clusters/$CLUSTER_ID/clusterregistrationtokens" 2>/dev/null)
    
    TOKEN_ID=$(echo "$TOKEN_RESPONSE" | jq -r '.name' 2>/dev/null)
    
    if [[ -z "$TOKEN_ID" ]] || [[ "$TOKEN_ID" == "null" ]]; then
      log_error "Failed to create registration token"
      echo "$TOKEN_RESPONSE" | jq '.'
      exit 1
    fi
    
    log_success "Created new registration token: $TOKEN_ID"
  else
    log_success "Found existing token: $TOKEN_ID"
  fi
  
  echo "$TOKEN_ID"
}

# Download and apply system-agent manifest
install_system_agent_on_node() {
  local node_ip="$1"
  local token_id="$2"
  
  log_info "Installing system-agent on $node_ip..."
  
  # Download manifest
  MANIFEST=$(curl -sk \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    "$RANCHER_URL/v3/import/${token_id}.yaml" 2>/dev/null)
  
  if [[ -z "$MANIFEST" ]]; then
    log_error "Failed to download manifest for token $token_id"
    return 1
  fi
  
  # Apply manifest on remote node
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would apply manifest to $node_ip"
    echo "$MANIFEST" | head -20
    echo "..."
  else
    log_info "Applying manifest to $node_ip..."
    
    ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      -o UserKnownHostsFile=/dev/null \
      "$SSH_USER@$node_ip" << EOSSH
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
echo "$MANIFEST" | sudo /var/lib/rancher/rke2/bin/kubectl apply -f -
echo "Waiting for system-agent to be ready..."
sleep 5
sudo /var/lib/rancher/rke2/bin/kubectl get -A pods -l app=rancher-system-agent
EOSSH
    
    if [ $? -eq 0 ]; then
      log_success "System-agent installed on $node_ip"
    else
      log_error "Failed to install system-agent on $node_ip"
      return 1
    fi
  fi
}

# Main function
main() {
  parse_args "$@"
  validate_inputs
  
  log_info "=========================================="
  log_info "Rancher System-Agent Installation"
  log_info "=========================================="
  log_info "Rancher URL: $RANCHER_URL"
  log_info "Cluster ID: $CLUSTER_ID"
  log_info "Nodes: ${NODES[@]}"
  log_info "SSH Key: $SSH_KEY"
  log_info "SSH User: $SSH_USER"
  [[ "$DRY_RUN" == "true" ]] && log_info "DRY RUN MODE"
  log_info ""
  
  # Get registration token
  TOKEN_ID=$(get_registration_token)
  log_success "Using token: $TOKEN_ID"
  log_info ""
  
  # Install on each node
  FAILED=0
  for node in "${NODES[@]}"; do
    install_system_agent_on_node "$node" "$TOKEN_ID" || FAILED=$((FAILED + 1))
  done
  
  log_info ""
  if [[ $FAILED -eq 0 ]]; then
    log_success "=========================================="
    log_success "System-agent installation complete!"
    log_success "=========================================="
    log_success "All nodes registered with Rancher"
    log_info ""
    log_info "Monitor progress in Rancher UI:"
    log_info "  $RANCHER_URL/dashboard/c/$CLUSTER_ID"
  else
    log_error "=========================================="
    log_error "Installation failed on $FAILED node(s)"
    log_error "=========================================="
    exit 1
  fi
}

main "$@"
