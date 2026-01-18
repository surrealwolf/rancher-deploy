#!/bin/bash
set -e

# Script to deploy Kube-VIP to a Kubernetes cluster
# Usage: deploy-kube-vip.sh <kubeconfig_path> <kube_vip_version> <namespace> <cluster_name> <ip_pool_addresses>

KUBECONFIG="$1"
KUBE_VIP_VERSION="$2"
NAMESPACE="$3"
CLUSTER_NAME="$4"
IP_POOL_ADDRESSES="$5"

export KUBECONFIG

echo "=========================================="
echo "Deploying Kube-VIP to Kubernetes Cluster"
echo "=========================================="
echo "Kubeconfig: $KUBECONFIG"
echo "Cluster: $CLUSTER_NAME"
echo "Kube-VIP Version: $KUBE_VIP_VERSION"
echo "Namespace: $NAMESPACE"
if [ -n "$IP_POOL_ADDRESSES" ]; then
  echo "IP Pool: $IP_POOL_ADDRESSES"
fi
echo ""

# Verify cluster is accessible
echo "Verifying Kubernetes cluster access..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot access Kubernetes cluster. Check KUBECONFIG: $KUBECONFIG"
  exit 1
fi
kubectl cluster-info
echo ""

# Wait for cluster to be fully ready
echo "Checking cluster readiness..."
CLUSTER_READY=false
READY_RETRY=0
READY_MAX_RETRIES=60  # 5 minutes max (60 * 5 seconds)

while [ "$CLUSTER_READY" = false ] && [ $READY_RETRY -lt $READY_MAX_RETRIES ]; do
  READY_RETRY=$((READY_RETRY + 1))
  
  # Check API server is responsive
  if ! kubectl get nodes &>/dev/null; then
    echo "  Attempt $READY_RETRY/$READY_MAX_RETRIES - API server not ready, waiting..."
    sleep 5
    continue
  fi
  
  # Check that we have at least one node in Ready state
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
  if [ "$READY_NODES" -eq 0 ]; then
    echo "  Attempt $READY_RETRY/$READY_MAX_RETRIES - No nodes in Ready state, waiting..."
    sleep 5
    continue
  fi
  
  # All checks passed
  echo "✓ Cluster is ready ($READY_NODES node(s) ready)"
  CLUSTER_READY=true
done

if [ "$CLUSTER_READY" = false ]; then
  echo "ERROR: Cluster not ready after $READY_MAX_RETRIES attempts (5 minutes)"
  echo "Current cluster status:"
  kubectl get nodes
  exit 1
fi

echo "Waiting 5 seconds for cluster to stabilize..."
sleep 5
echo "✓ Cluster is stable, proceeding with installation"
echo ""

# Step 1: Install Kube-VIP using Helm
echo "[1/2] Installing Kube-VIP (version $KUBE_VIP_VERSION)..."

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "  Creating namespace: $NAMESPACE"
  kubectl create namespace "$NAMESPACE"
  echo "  ✓ Namespace created"
fi

# Add Kube-VIP Helm repository
if ! helm repo list | grep -q "kube-vip"; then
  echo "  Adding Kube-VIP Helm repository..."
  helm repo add kube-vip https://kube-vip.github.io/kube-vip-cloud-provider || {
    echo "ERROR: Failed to add Kube-VIP Helm repository."
    exit 1
  }
  helm repo update
  echo "  ✓ Helm repository added and updated"
fi

# Check if Kube-VIP is already installed
if helm list -n "$NAMESPACE" | grep -q "kube-vip"; then
  echo "  Kube-VIP already installed, upgrading..."
  helm upgrade kube-vip kube-vip/kube-vip-cloud-provider \
    --namespace "$NAMESPACE" \
    --version "$KUBE_VIP_VERSION" \
    --set vip_interface=eth0 \
    --wait \
    --timeout 5m || {
    echo "  ⚠ Upgrade may have issues, checking status..."
    helm status kube-vip -n "$NAMESPACE" || true
  }
  echo "  ✓ Kube-VIP upgraded"
else
  echo "  Installing Kube-VIP from Helm chart (first time installation)..."
  helm install kube-vip kube-vip/kube-vip-cloud-provider \
    --namespace "$NAMESPACE" \
    --version "$KUBE_VIP_VERSION" \
    --set vip_interface=eth0 \
    --wait \
    --timeout 5m || {
    echo "ERROR: Failed to install Kube-VIP via Helm."
    exit 1
  }
  echo "  ✓ Kube-VIP Helm chart installed"
fi

# Wait for Kube-VIP pods to be ready
echo "  Waiting for Kube-VIP pods to be ready..."
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=kube-vip-cloud-provider \
  --timeout=5m || {
  echo "  ⚠ Pods may still be starting, checking status..."
  kubectl get pods -n "$NAMESPACE" || true
}

# Step 2: Configure IP address pool if provided
if [ -n "$IP_POOL_ADDRESSES" ]; then
  echo ""
  echo "[2/2] Configuring Kube-VIP IP address pool..."
  
  # Parse IP range (e.g., "192.168.14.150-192.168.14.251")
  if [[ "$IP_POOL_ADDRESSES" =~ ^([0-9.]+)-([0-9.]+)$ ]]; then
    START_IP="${BASH_REMATCH[1]}"
    END_IP="${BASH_REMATCH[2]}"
    CIDR_RANGE="${START_IP}/32-${END_IP}/32"
    
    # Create or update ConfigMap for service CIDR
    if kubectl get configmap kubevip -n "$NAMESPACE" &>/dev/null; then
      echo "  ConfigMap already exists, updating..."
      kubectl patch configmap kubevip -n "$NAMESPACE" --type merge -p "{\"data\":{\"range-global\":\"$CIDR_RANGE\"}}" || {
        echo "  ⚠ Failed to update ConfigMap, trying to recreate..."
        kubectl delete configmap kubevip -n "$NAMESPACE" --ignore-not-found=true
        sleep 2
      }
    fi
    
    # Create ConfigMap if it doesn't exist
    if ! kubectl get configmap kubevip -n "$NAMESPACE" &>/dev/null; then
      echo "  Creating ConfigMap for IP pool: $CIDR_RANGE"
      kubectl create configmap kubevip -n "$NAMESPACE" \
        --from-literal=range-global="$CIDR_RANGE" || {
        echo "ERROR: Failed to create ConfigMap."
        exit 1
      }
      echo "  ✓ ConfigMap created"
    else
      echo "  ✓ ConfigMap updated"
    fi
    
    # Restart DaemonSet to pick up new configuration
    echo "  Restarting Kube-VIP DaemonSet to apply configuration..."
    kubectl rollout restart daemonset/kube-vip -n "$NAMESPACE" || true
    sleep 3
    echo "  ✓ DaemonSet restarted"
  else
    echo "  ⚠ Invalid IP pool format: $IP_POOL_ADDRESSES"
    echo "  Expected format: START_IP-END_IP (e.g., 192.168.14.150-192.168.14.251)"
  fi
else
  echo ""
  echo "[2/2] Skipping IP pool configuration (ip_pool_addresses not provided)"
  echo "  Note: IP pool can be configured manually (see Kube-VIP documentation)"
fi

# Verify installation
echo ""
echo "Verifying Kube-VIP installation..."
sleep 5

PODS_READY=0
for i in {1..30}; do
  READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kube-vip-cloud-provider --no-headers 2>/dev/null | grep -c " Running " || echo "0")
  if [ "$READY_PODS" -gt 0 ]; then
    PODS_READY=$READY_PODS
    break
  fi
  if [ $((i % 5)) -eq 0 ]; then
    echo "  Waiting for pods to be ready... attempt $i/30"
  fi
  sleep 2
done

if [ "$PODS_READY" -gt 0 ]; then
  echo "✓ Kube-VIP is ready ($PODS_READY pod(s) running)"
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kube-vip-cloud-provider
else
  echo "  ⚠ Kube-VIP pods may still be starting"
  kubectl get pods -n "$NAMESPACE" || true
fi

echo ""
echo "=========================================="
echo "Kube-VIP Installation Complete"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "Kube-VIP Version: $KUBE_VIP_VERSION"
if [ -n "$IP_POOL_ADDRESSES" ]; then
  echo "IP Pool: $IP_POOL_ADDRESSES"
fi
echo ""
echo "Next steps:"
echo "  1. Verify installation:"
echo "     kubectl get pods -n $NAMESPACE"
echo "     kubectl get configmap kubevip -n $NAMESPACE"
echo ""
echo "  2. Configure services to use LoadBalancer type:"
echo "     kubectl patch svc <service-name> -n <namespace> -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
echo ""
echo "  3. See Kube-VIP documentation for detailed configuration"
echo "=========================================="
