#!/bin/bash

# Script to configure kubeconfig for deployed clusters

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
KUBE_DIR="$HOME/.kube"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$KUBE_DIR"

echo "Rancher Kubeconfig Configuration"
echo "=================================="
echo ""

# Manager cluster
echo -e "${YELLOW}Configuring manager cluster kubeconfig...${NC}"
read -p "Enter manager cluster server IP (e.g., 192.168.1.100): " MANAGER_IP

scp "ubuntu@$MANAGER_IP:/etc/rancher/rke2/rke2.yaml" "$KUBE_DIR/rancher-manager-config" || {
    echo "Failed to retrieve kubeconfig from manager"
    exit 1
}

# Update server IP
sed -i "s/127.0.0.1/$MANAGER_IP/g" "$KUBE_DIR/rancher-manager-config"
chmod 600 "$KUBE_DIR/rancher-manager-config"

echo -e "${GREEN}✓ Manager kubeconfig saved to $KUBE_DIR/rancher-manager-config${NC}"

# NPRD-Apps cluster
echo -e "${YELLOW}Configuring nprd-apps cluster kubeconfig...${NC}"
read -p "Enter nprd-apps cluster server IP (e.g., 192.168.2.100): " NPRD_IP

scp "ubuntu@$NPRD_IP:/etc/rancher/rke2/rke2.yaml" "$KUBE_DIR/nprd-apps-config" || {
    echo "Failed to retrieve kubeconfig from nprd-apps"
    exit 1
}

# Update server IP
sed -i "s/127.0.0.1/$NPRD_IP/g" "$KUBE_DIR/nprd-apps-config"
chmod 600 "$KUBE_DIR/nprd-apps-config"

echo -e "${GREEN}✓ NPRD-Apps kubeconfig saved to $KUBE_DIR/nprd-apps-config${NC}"

# Create context switching aliases
echo ""
echo "Adding context switch aliases to ~/.bashrc..."

cat >> ~/.bashrc <<'EOF'

# Rancher cluster aliases
alias kctx-manager='export KUBECONFIG=$HOME/.kube/rancher-manager-config'
alias kctx-nprd='export KUBECONFIG=$HOME/.kube/nprd-apps-config'
alias kctx-all='export KUBECONFIG=$HOME/.kube/rancher-manager-config:$HOME/.kube/nprd-apps-config'

# Quick cluster info
alias k-manager-nodes='KUBECONFIG=$HOME/.kube/rancher-manager-config kubectl get nodes'
alias k-nprd-nodes='KUBECONFIG=$HOME/.kube/nprd-apps-config kubectl get nodes'
EOF

source ~/.bashrc

echo -e "${GREEN}✓ Aliases configured${NC}"
echo ""
echo "Usage:"
echo "  kctx-manager  - Switch to manager cluster"
echo "  kctx-nprd     - Switch to nprd-apps cluster"
echo "  kctx-all      - Set both clusters"
echo ""
echo "Quick commands:"
echo "  k-manager-nodes - List manager cluster nodes"
echo "  k-nprd-nodes    - List nprd-apps cluster nodes"
