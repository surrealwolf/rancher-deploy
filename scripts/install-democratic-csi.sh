#!/bin/bash

# Democratic CSI Installation Script for TrueNAS
# Pre-configured with your TrueNAS details

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="democratic-csi"
RELEASE_NAME="democratic-csi"
VALUES_FILE="helm-values/democratic-csi-truenas.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Democratic CSI Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Generate values from tfvars
echo -e "${YELLOW}Generating Helm values from terraform.tfvars...${NC}"
if [ ! -f "terraform/terraform.tfvars" ]; then
    echo "Error: terraform.tfvars not found"
    echo "Please configure TrueNAS settings in terraform/terraform.tfvars"
    exit 1
fi

if [ ! -f "scripts/generate-helm-values-from-tfvars.sh" ]; then
    echo "Error: generate-helm-values-from-tfvars.sh not found"
    exit 1
fi

if ! ./scripts/generate-helm-values-from-tfvars.sh; then
    echo "Error: Failed to generate Helm values from terraform.tfvars"
    exit 1
fi

if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: Generated values file not found: $VALUES_FILE"
    exit 1
fi

echo -e "${GREEN}✓ Using values file: ${VALUES_FILE}${NC}"

echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
fi
echo "✓ kubectl found"

if ! command -v helm &> /dev/null; then
    echo "Error: helm not found"
    exit 1
fi
echo "✓ helm found"

# Set kubeconfig
if [ -f "$HOME/.kube/nprd-apps.yaml" ]; then
    export KUBECONFIG="$HOME/.kube/nprd-apps.yaml"
    echo "✓ Using kubeconfig: ~/.kube/nprd-apps.yaml"
else
    echo "⚠ Using default kubeconfig"
fi

# Verify cluster access
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot access Kubernetes cluster"
    exit 1
fi
echo "✓ Cluster access verified"
echo ""

# Add Helm repository
echo -e "${YELLOW}Adding Helm repository...${NC}"
helm repo add democratic-csi https://democratic-csi.github.io/charts/ 2>/dev/null || echo "Repository already added"
helm repo update
echo "✓ Helm repository ready"
echo ""

# Create namespace
echo -e "${YELLOW}Creating namespace...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Namespace created"
echo ""

# Install democratic-csi
echo -e "${YELLOW}Installing democratic-csi...${NC}"
echo "Using values file: $ACTUAL_VALUES_FILE"
echo ""

helm upgrade --install "$RELEASE_NAME" democratic-csi/democratic-csi \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --wait \
  --timeout 10m

echo ""
echo -e "${GREEN}✓ Democratic CSI installed${NC}"
echo ""

# Wait for pods
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=democratic-csi-controller -n "$NAMESPACE" --timeout=5m || true
kubectl wait --for=condition=ready pod -l app=democratic-csi-node -n "$NAMESPACE" --timeout=5m || true

# Verify installation
echo ""
echo -e "${YELLOW}Verifying installation...${NC}"
echo ""
echo "Pods:"
kubectl get pods -n "$NAMESPACE"
echo ""
echo "Storage Classes:"
kubectl get storageclass
echo ""

# Check for default storage class conflicts
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -n "$DEFAULT_SC" ]; then
    echo -e "${YELLOW}Current default storage class: ${DEFAULT_SC}${NC}"
    if [ "$DEFAULT_SC" != "truenas-nfs" ]; then
        echo -e "${YELLOW}⚠️  Warning: Another storage class is already default${NC}"
        echo "To make truenas-nfs the default, run:"
        echo "  kubectl patch storageclass $DEFAULT_SC -p '{\"metadata\": {\"annotations\": {\"storageclass.kubernetes.io/is-default-class\": \"false\"}}}'"
        echo "  kubectl patch storageclass truenas-nfs -p '{\"metadata\": {\"annotations\": {\"storageclass.kubernetes.io/is-default-class\": \"true\"}}}'"
    else
        echo -e "${GREEN}✓ truenas-nfs is the default storage class${NC}"
    fi
else
    echo -e "${GREEN}✓ truenas-nfs is the default storage class${NC}"
fi

echo ""
echo "CSI Drivers:"
kubectl get csidriver

# Test PVC
echo ""
read -p "Create a test PVC? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Creating test PVC...${NC}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-democratic-csi
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: truenas-nfs
  resources:
    requests:
      storage: 10Gi
EOF
    
    echo "Waiting for PVC to be bound..."
    kubectl wait --for=condition=Bound pvc/test-pvc-democratic-csi --timeout=2m || echo "PVC may take longer to bind"
    
    echo ""
    echo "PVC Status:"
    kubectl get pvc test-pvc-democratic-csi
    
    echo ""
    echo -e "${GREEN}Test PVC created!${NC}"
    echo "To delete: kubectl delete pvc test-pvc-democratic-csi"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Verify storage class: kubectl get storageclass"
echo "2. Create PVCs using storageClassName: truenas-nfs"
echo "3. Check TrueNAS UI for created volumes"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE -l app=democratic-csi-controller"
echo "  kubectl get pvc --all-namespaces"
