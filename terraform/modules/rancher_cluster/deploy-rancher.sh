#!/bin/bash
set -e

# Script to deploy Rancher and cert-manager to a Kubernetes cluster
# Usage: deploy-rancher.sh <kubeconfig_path> <rancher_version> <rancher_hostname> <rancher_password> <cert_manager_version>

KUBECONFIG="$1"
RANCHER_VERSION="$2"
RANCHER_HOSTNAME="$3"
RANCHER_PASSWORD="$4"
CERT_MANAGER_VERSION="$5"

export KUBECONFIG

echo "=========================================="
echo "Deploying Rancher to Kubernetes Cluster"
echo "=========================================="
echo "Kubeconfig: $KUBECONFIG"
echo "Rancher Version: $RANCHER_VERSION"
echo "Rancher Hostname: $RANCHER_HOSTNAME"
echo "Cert-Manager Version: $CERT_MANAGER_VERSION"
echo ""

# Verify cluster is accessible
echo "Verifying Kubernetes cluster access..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot access Kubernetes cluster. Check KUBECONFIG: $KUBECONFIG"
  exit 1
fi
kubectl cluster-info
echo ""

# Add helm repos
echo "Adding Helm repositories..."
helm repo add jetstack https://charts.jetstack.io --force-update || true
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update || true
helm repo update
echo "✓ Helm repositories updated"
echo ""

# Install cert-manager
echo "Installing cert-manager..."
kubectl create namespace cert-manager 2>/dev/null || true
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --version "$CERT_MANAGER_VERSION" \
  --wait \
  --timeout 10m \
  || {
    echo "ERROR: Failed to install cert-manager"
    exit 1
  }
echo "✓ cert-manager installed"
echo ""

# Wait for cert-manager to be ready
echo "Waiting for cert-manager deployment..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=5m
echo "✓ cert-manager is ready"
echo ""

# Install Rancher
echo "Installing Rancher..."
kubectl create namespace cattle-system 2>/dev/null || true
helm upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname="$RANCHER_HOSTNAME" \
  --set replicas=3 \
  --set bootstrapPassword="$RANCHER_PASSWORD" \
  --version "$RANCHER_VERSION" \
  --wait \
  --timeout 15m \
  || {
    echo "ERROR: Failed to install Rancher"
    exit 1
  }
echo "✓ Rancher installed"
echo ""

# Wait for Rancher to be ready
echo "Waiting for Rancher deployment..."
kubectl rollout status deployment/rancher -n cattle-system --timeout=10m
echo "✓ Rancher is ready"
echo ""

# Display summary
echo "=========================================="
echo "✓ Deployment Complete!"
echo "=========================================="
echo ""
echo "Rancher URL: https://$RANCHER_HOSTNAME"
echo "Bootstrap Password: $RANCHER_PASSWORD"
echo ""
echo "Access with:"
echo "  Username: admin"
echo "  Password: $RANCHER_PASSWORD"
echo ""

# Get ingress info
echo "Ingress Information:"
kubectl get ingress -n cattle-system
echo ""

# Get Rancher pod status
echo "Rancher Pod Status:"
kubectl get pods -n cattle-system
echo ""

# Test Rancher URL accessibility
echo "Testing Rancher URL accessibility..."
RETRY_COUNT=0
MAX_RETRIES=30
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -k -s -o /dev/null -w "%{http_code}" "https://$RANCHER_HOSTNAME" | grep -q "200"; then
    echo "✓ Rancher is accessible at https://$RANCHER_HOSTNAME"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "  Attempt $RETRY_COUNT/$MAX_RETRIES - Waiting for Rancher to be ready..."
    sleep 10
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "WARNING: Rancher URL is not responding after $MAX_RETRIES attempts"
  echo "Please verify DNS resolution and firewall rules"
fi
echo ""

# ============================================================================
# CREATE RANCHER API TOKEN FOR DOWNSTREAM CLUSTER REGISTRATION
# ============================================================================

echo "Creating Rancher API token for downstream cluster registration..."
echo ""

# Step 1: Authenticate with Rancher using admin credentials
echo "Step 1: Authenticating with Rancher..."
LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$RANCHER_PASSWORD\"}" \
  -k "https://$RANCHER_HOSTNAME/v3-public/localProviders/local?action=login")

# Extract temporary token
TEMP_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$TEMP_TOKEN" ]; then
  echo "WARNING: Failed to authenticate with Rancher API"
  echo "  Response: $LOGIN_RESPONSE"
  echo "  Skipping API token creation - you can create it manually later"
  echo ""
else
  echo "✓ Authenticated with Rancher"
  echo ""

  # Step 2: Create permanent API token
  echo "Step 2: Creating API token..."
  TOKEN_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $TEMP_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "type": "token",
      "description": "Terraform automation token for downstream cluster registration",
      "ttl": 0,
      "isDerived": false
    }' \
    -k "https://$RANCHER_HOSTNAME/v3/tokens")

  # Extract the API token
  API_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | head -1 | cut -d'"' -f4)

  if [ -z "$API_TOKEN" ]; then
    echo "WARNING: Failed to create API token"
    echo "  Response: $TOKEN_RESPONSE"
    echo "  You can create the token manually via Rancher UI or script"
    echo ""
  else
    echo "✓ API token created successfully"
    echo ""
    echo "=========================================="
    echo "Rancher API Token:"
    echo "=========================================="
    echo "$API_TOKEN"
    echo ""
    echo "Token saved. Add to terraform/terraform.tfvars:"
    echo "  rancher_api_token = \"$API_TOKEN\""
    echo ""
  fi
fi

# Merge kubeconfig to default kubeconfig
echo "Merging kubeconfig to ~/.kube/config..."
if [ -f "$KUBECONFIG" ]; then
  # Create backup
  if [ -f ~/.kube/config ]; then
    cp ~/.kube/config ~/.kube/config.backup
    echo "  Backup created: ~/.kube/config.backup"
  fi
  
  # Merge kubeconfigs using kubectl
  KUBECONFIG=~/.kube/config:"$KUBECONFIG" kubectl config view --flatten > ~/.kube/config.tmp
  mv ~/.kube/config.tmp ~/.kube/config
  chmod 600 ~/.kube/config
  echo "✓ Kubeconfig merged to ~/.kube/config"
  echo "  You can now use: kubectl --context=<cluster-name> get nodes"
else
  echo "WARNING: Kubeconfig not found at $KUBECONFIG"
fi
echo ""

echo "=========================================="
