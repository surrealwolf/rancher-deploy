#!/bin/bash

# RKE2 Installation Script - Simplified & Robust
# Works on fresh VMs and can be re-run safely on existing VMs

LOG_FILE="/var/log/rke2-install.log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== RKE2 Installation Script Starting ==="

# Skip checks if already installed
if [ -f /usr/local/bin/rke2 ]; then
  log "RKE2 already installed, skipping installation"
  exit 0
fi

# Wait for cloud-init to complete (CRITICAL - system must be fully ready)
# Use boot-finished file check (more reliable than cloud-init status --wait which can hang)
log "Waiting for cloud-init to complete..."
CLOUD_INIT_ATTEMPTS=0
MAX_CLOUD_INIT_ATTEMPTS=120  # 10 minutes max (120 × 5 sec = 600 sec)

while [ $CLOUD_INIT_ATTEMPTS -lt $MAX_CLOUD_INIT_ATTEMPTS ]; do
  CLOUD_INIT_ATTEMPTS=$((CLOUD_INIT_ATTEMPTS + 1))
  
  # Check for boot-finished file (reliable indicator that cloud-init completed)
  if [ -f /var/lib/cloud/instance/boot-finished ]; then
    log "✓ Cloud-init completed at attempt $CLOUD_INIT_ATTEMPTS ($(($CLOUD_INIT_ATTEMPTS * 5)) seconds)"
    break
  fi
  
  if [ $((CLOUD_INIT_ATTEMPTS % 12)) -eq 0 ]; then
    ELAPSED=$((CLOUD_INIT_ATTEMPTS * 5))
    log "  Still waiting for cloud-init... attempt $CLOUD_INIT_ATTEMPTS/120 (${ELAPSED}s elapsed)"
  fi
  sleep 5
done

if [ $CLOUD_INIT_ATTEMPTS -ge $MAX_CLOUD_INIT_ATTEMPTS ]; then
  log "⚠ Cloud-init boot-finished not found after 10 minutes, but proceeding (system may still be initializing)"
fi

# Create .kube directory and placeholder kubeconfig for Terraform provider validation
# The real kubeconfig will be written by RKE2 when it's ready
log "Setting up kubeconfig directory..."
sudo mkdir -p /root/.kube /home/ubuntu/.kube
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube
sudo chmod 700 /home/ubuntu/.kube

# Create placeholder kubeconfig so Terraform Kubernetes provider can validate it exists
# This will be overwritten by the actual RKE2 config once the cluster is ready
sudo tee /home/ubuntu/.kube/rancher-manager.yaml > /dev/null << 'EOF'
apiVersion: v1
kind: Config
metadata:
  name: rancher-manager
clusters:
- cluster:
    server: https://placeholder:6443
  name: rancher-manager
contexts:
- context:
    cluster: rancher-manager
    user: admin@rancher-manager
  name: rancher-manager
current-context: rancher-manager
users:
- name: admin@rancher-manager
  user:
    token: placeholder
EOF

sudo chown ubuntu:ubuntu /home/ubuntu/.kube/rancher-manager.yaml
sudo chmod 600 /home/ubuntu/.kube/rancher-manager.yaml
log "✓ Placeholder kubeconfig created (will be overwritten by RKE2 when ready)"

# Verify network connectivity with retries
log "Verifying network connectivity..."
NETWORK_ATTEMPTS=0
while [ $NETWORK_ATTEMPTS -lt 5 ]; do
  NETWORK_ATTEMPTS=$((NETWORK_ATTEMPTS + 1))
  if timeout 10 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log "✓ Network connectivity verified"
    break
  fi
  if [ $NETWORK_ATTEMPTS -lt 5 ]; then
    log "  Network not ready, retry $NETWORK_ATTEMPTS/5..."
    sleep 2
  fi
done

if [ $NETWORK_ATTEMPTS -ge 5 ]; then
  log "⚠ Network verification failed after 5 attempts, proceeding anyway"
fi

# Update packages
log "Updating package list..."
apt-get update -qq || log "⚠ Package update failed"

# Download RKE2 installer with timeout and retries
log "Downloading RKE2 installer..."
INSTALLER="/tmp/rke2-installer.sh"
DOWNLOAD_SUCCESS=0

for i in {1..5}; do
  log "Download attempt $i/5..."
  CURL_OUTPUT=$(timeout 60 curl -sfL --max-time 60 --connect-timeout 30 https://get.rke2.io -o "$INSTALLER" 2>&1)
  CURL_EXIT=$?
  
  if [ $CURL_EXIT -eq 0 ] && [ -f "$INSTALLER" ] && [ -s "$INSTALLER" ]; then
    log "✓ RKE2 installer downloaded successfully"
    chmod +x "$INSTALLER"
    DOWNLOAD_SUCCESS=1
    break
  else
    if [ $CURL_EXIT -ne 0 ]; then
      log "  curl exit code: $CURL_EXIT, error: $CURL_OUTPUT"
    elif [ ! -f "$INSTALLER" ]; then
      log "  File not created after download"
    elif [ ! -s "$INSTALLER" ]; then
      log "  File is empty after download"
    fi
  fi
  
  if [ $i -lt 5 ]; then
    log "Download failed, retrying in 10 seconds..."
    sleep 10
  fi
done

if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
  log "✗ Failed to download RKE2 installer after 5 attempts"
  exit 1
fi


# ============ RKE2 SERVER NODE ============
if [ "${IS_RKE2_SERVER}" = "true" ]; then
log "Installing RKE2 server v${RKE2_VERSION}..."

export INSTALL_RKE2_VERSION="${RKE2_VERSION}"

# If SERVER_IP is provided, this is a secondary node joining primary's cluster
if [ -n "${SERVER_IP}" ] && [ "${SERVER_IP}" != "" ]; then
  # Secondary node MUST have a token passed from Terraform
  if [ -z "${SERVER_TOKEN}" ] || [ "${SERVER_TOKEN}" = "" ]; then
    log "✗ ERROR: Secondary server detected but no token provided by Terraform"
    log "ℹ Token should be fetched from primary and passed via rke2_server_token variable"
    log "ℹ Check Terraform logs for token fetch failures"
    exit 1
  fi
  log "Secondary server detected. Joining existing RKE2 cluster at ${SERVER_IP}:9345..."
  
  # CRITICAL: Wait for primary registration API to be responsive before joining (port 9345, not 6443!)
  log "Waiting for primary RKE2 registration API (${SERVER_IP}:9345) to be ready..."
  API_READY=0
  for i in {1..120}; do
    if timeout 5 bash -c "echo > /dev/tcp/${SERVER_IP}/9345" 2>/dev/null; then
      log "✓ Primary registration port is accessible at attempt $i"
      API_READY=1
      break
    fi
    if [ $((i % 10)) -eq 0 ] || [ $i -le 3 ]; then
      log "  Primary port check attempt $i/120..."
    fi
    sleep 5
  done
  
  if [ $API_READY -eq 0 ]; then
    log "✗ ERROR: Primary registration API did not become ready after 10 minutes"
    log "ℹ Verify primary RKE2 server is running: systemctl status rke2-server on ${SERVER_IP}"
    log "ℹ Check primary logs: journalctl -u rke2-server on ${SERVER_IP}"
    exit 1
  fi
  
  # Create config file for secondary node BEFORE running installer
  # RKE2 reads this automatically and joins primary's etcd cluster
  mkdir -p /etc/rancher/rke2
  cat > /etc/rancher/rke2/config.yaml <<'EOF'
# Secondary RKE2 server - join primary cluster via shared etcd
server: https://SERVER_IP_PLACEHOLDER:9345
token: SERVER_TOKEN_PLACEHOLDER
tls-san:
  - ${CLUSTER_HOSTNAME}
  - ${CLUSTER_PRIMARY_IP}
EOF
  # Add aliases if provided
  if [ -n "${CLUSTER_ALIASES}" ] && [ "${CLUSTER_ALIASES}" != "" ]; then
    IFS=',' read -ra ALIASES_ARRAY <<< "${CLUSTER_ALIASES}"
    for ALIAS in "${ALIASES_ARRAY[@]}"; do
      echo "  - $ALIAS" >> /etc/rancher/rke2/config.yaml
    done
  fi
  # Replace placeholders with actual values
  sed -i "s|SERVER_IP_PLACEHOLDER|${SERVER_IP}|g" /etc/rancher/rke2/config.yaml
  sed -i "s|SERVER_TOKEN_PLACEHOLDER|${SERVER_TOKEN}|g" /etc/rancher/rke2/config.yaml
  log "✓ RKE2 secondary config created at /etc/rancher/rke2/config.yaml"
  
else
  log "Starting new RKE2 server (primary node)"
  # Create config file for primary node
  mkdir -p /etc/rancher/rke2
  cat > /etc/rancher/rke2/config.yaml <<'EOF'
# Primary RKE2 server with HA etcd clustering
tls-san:
  - ${CLUSTER_HOSTNAME}
  - ${CLUSTER_PRIMARY_IP}
EOF
  # Add aliases if provided
  if [ -n "${CLUSTER_ALIASES}" ] && [ "${CLUSTER_ALIASES}" != "" ]; then
    IFS=',' read -ra ALIASES_ARRAY <<< "${CLUSTER_ALIASES}"
    for ALIAS in "${ALIASES_ARRAY[@]}"; do
      echo "  - $ALIAS" >> /etc/rancher/rke2/config.yaml
    done
  fi
  log "✓ RKE2 primary config created at /etc/rancher/rke2/config.yaml"
fi

# Install RKE2 - will automatically read config.yaml for all settings
export INSTALL_RKE2_VERSION="${RKE2_VERSION}"

if ! "$INSTALLER"; then
  log "✗ RKE2 installation failed"
  exit 1
fi

log "RKE2 installation complete. Service will start automatically."
log "ⓘ Note: RKE2 service may take several minutes to fully initialize"
log "ⓘ You can check status later with: systemctl status rke2-server"

log "✓ RKE2 server installation complete"

# Verify systemd unit exists, then enable and start if needed
if [ -f /usr/local/lib/systemd/system/rke2-server.service ]; then
  if ! systemctl is-active --quiet rke2-server; then
    log "Enabling and starting RKE2 server service..."
    systemctl daemon-reload
    systemctl enable rke2-server
    systemctl start rke2-server
    log "✓ RKE2 server service enabled and started"
  else
    log "✓ RKE2 server service is already running"
  fi
else
  log "⚠ RKE2 server unit file not found, service will start manually"
fi

else
# ============ RKE2 AGENT NODE ============
log "Installing RKE2 agent v${RKE2_VERSION} (server: ${SERVER_IP})..."

# Create environment file for rke2-agent service BEFORE installation
mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/rke2.env <<EOF
RKE2_URL="https://${SERVER_IP}:6443"
RKE2_TOKEN="${SERVER_TOKEN}"
RKE2_AGENT_TAINTS=""
EOF
log "✓ RKE2 agent environment file created"

export RKE2_URL="https://${SERVER_IP}:6443"
export RKE2_TOKEN="${SERVER_TOKEN}"
export INSTALL_RKE2_VERSION="${RKE2_VERSION}"

if ! "$INSTALLER"; then
  log "✗ RKE2 installation failed"
  exit 1
fi

log "RKE2 agent installation complete. Service will start automatically."
log "ⓘ Note: RKE2 agent may take several minutes to join the cluster"
log "ⓘ You can check status later with: systemctl status rke2-agent"

# Verify systemd unit exists, then enable and start if needed
if [ -f /usr/local/lib/systemd/system/rke2-agent.service ]; then
  if ! systemctl is-active --quiet rke2-agent; then
    log "Enabling and starting RKE2 agent service..."
    systemctl daemon-reload
    systemctl enable rke2-agent
    systemctl start rke2-agent
    log "✓ RKE2 agent service enabled and started"
  else
    log "✓ RKE2 agent service is already running"
  fi
else
  log "⚠ RKE2 agent unit file not found, service will start manually"
fi
fi

# Setup kubeconfig access
log "Setting up kubectl access..."
cat >> /root/.bashrc <<'BASHEOF'
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="${PATH}:/usr/local/bin"
alias k=kubectl
BASHEOF

log "=== RKE2 Installation Script Completed Successfully ==="
