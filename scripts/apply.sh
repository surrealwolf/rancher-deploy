#!/bin/bash
# Terraform plan + apply with automatic logging
# Runs plan in background, then applies
# Usage: ./scripts/apply.sh [terraform-args]

set -e

LOG_DIR="../logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/terraform-$(date +%s).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "═══════════════════════════════════════════════════════════"
echo "Terraform Plan + Apply with Logging"
echo "═══════════════════════════════════════════════════════════"
echo "Timestamp: $TIMESTAMP"
echo "Log Level: DEBUG"
echo "Log File: $LOG_FILE"
echo "───────────────────────────────────────────────────────────"

cd "$(dirname "$(cd "$(dirname "$0")" && pwd)")/terraform"

# Enable debug logging
export TF_LOG=debug
export TF_LOG_PATH="$LOG_FILE"

# Run plan in foreground
echo "Starting terraform plan..."
/usr/bin/terraform plan -out=tfplan "$@"
PLAN_EXIT=$?

if [ $PLAN_EXIT -ne 0 ]; then
  echo "Plan failed with exit code $PLAN_EXIT"
  exit $PLAN_EXIT
fi

echo ""
echo "Plan complete, starting apply in background..."
echo "PID: $$"
echo "Logs: $LOG_FILE"
echo ""

# Run apply in background
/usr/bin/terraform apply tfplan >> "$LOG_FILE" 2>&1 &
APPLY_PID=$!

echo "Apply started (PID: $APPLY_PID)"
echo "You can monitor progress with:"
echo "  tail -f $LOG_FILE"
