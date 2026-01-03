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

# Wait for cloud-init completion (with timeout to prevent hanging)
log "Waiting for cloud-init to complete..."
timeout 120 cloud-init status --wait 2>/dev/null || log "⚠ Cloud-init wait timed out, proceeding anyway"

# Verify network connectivity
log "Verifying network connectivity..."
if ! timeout 30 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  log "⚠ Network verification failed, proceeding anyway"
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
  log "Secondary server detected. Joining existing RKE2 cluster at ${SERVER_IP}..."
  export RKE2_URL="https://${SERVER_IP}:6443"
  export RKE2_TOKEN="${SERVER_TOKEN}"
else
  log "Starting new RKE2 server (primary node)"
fi

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
