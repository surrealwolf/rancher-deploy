#!/bin/bash
# Terraform destroy with automatic logging and cleanup
# Similar to apply.sh but for infrastructure teardown
# Usage: ./destroy.sh [terraform-args]

set -e

LOG_FILE="terraform-destroy-$(date +%s).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "═══════════════════════════════════════════════════════════"
echo "Terraform Destroy with Logging and Cleanup"
echo "═══════════════════════════════════════════════════════════"
echo "Timestamp: $TIMESTAMP"
echo "Log Level: DEBUG"
echo "Log File: terraform/$LOG_FILE"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "⚠️  WARNING: This will destroy ALL infrastructure"
echo ""
echo "This action will:"
echo "  - Delete all Rancher manager and apps cluster VMs"
echo "  - Remove cloud images from Proxmox"
echo "  - Clean up local token files and kubeconfig"
echo ""

# Prompt for confirmation
read -p "Type 'destroy-all' to continue, or press Ctrl+C to cancel: " confirm

if [ "$confirm" != "destroy-all" ]; then
  echo "Destroy cancelled"
  exit 0
fi

cd /home/lee/git/rancher-deploy/terraform

# Enable debug logging
export TF_LOG=debug
export TF_LOG_PATH="$LOG_FILE"

echo ""
echo "Starting terraform destroy in background..."
echo "PID: $$"
echo "Logs: terraform/$LOG_FILE"
echo ""

# Run destroy in background with auto-approve
/usr/bin/terraform destroy -auto-approve "$@" >> "$LOG_FILE" 2>&1 &
DESTROY_PID=$!

echo "Destroy started (PID: $DESTROY_PID)"
echo "You can monitor progress with:"
echo "  tail -f terraform/$LOG_FILE"
echo ""

# Wait for destroy to complete
wait $DESTROY_PID
DESTROY_EXIT=$?

if [ $DESTROY_EXIT -eq 0 ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "Cleanup: Removing local files..."
  echo "───────────────────────────────────────────────────────────"
  
  # Clean up token files
  rm -fv /home/lee/git/rancher-deploy/terraform/.manager-token 2>/dev/null || true
  
  # Clean up kubeconfig
  rm -fv ~/.kube/rancher-manager.yaml 2>/dev/null || true
  
  echo "═══════════════════════════════════════════════════════════"
  echo "✓ Infrastructure destroyed successfully"
  echo "═══════════════════════════════════════════════════════════"
else
  echo ""
  echo "⚠️  Destroy failed with exit code $DESTROY_EXIT"
  echo "Check logs for details: terraform/$LOG_FILE"
  exit $DESTROY_EXIT
fi
