#!/bin/bash
# Terraform apply with automatic logging
# Usage: ./apply.sh [plan-file]
# or: ./apply.sh (auto-approve mode)

set -e

LOG_FILE="terraform-$(date +%s).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "═══════════════════════════════════════════════════════════"
echo "Terraform Apply with Logging"
echo "═══════════════════════════════════════════════════════════"
echo "Timestamp: $TIMESTAMP"
echo "Log Level: DEBUG"
echo "Log File: terraform/$LOG_FILE"
echo "Command: terraform apply ${@}"
echo "───────────────────────────────────────────────────────────"

cd /home/lee/git/rancher-deploy/terraform

# Enable debug logging and run terraform apply
export TF_LOG=debug
export TF_LOG_PATH="$LOG_FILE"

echo "Starting deployment..."
/usr/bin/terraform apply "$@"
EXIT_CODE=$?

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Deployment Complete"
echo "═══════════════════════════════════════════════════════════"
echo "Exit Code: $EXIT_CODE"
echo "Logs saved to: terraform/$LOG_FILE"
echo ""

# Show last 50 lines of log
echo "Last 50 lines of log:"
echo "───────────────────────────────────────────────────────────"
tail -50 "$LOG_FILE"

exit $EXIT_CODE
