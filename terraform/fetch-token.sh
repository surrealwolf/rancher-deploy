#!/bin/bash
# Fetch RKE2 token from primary node

set -e

SSH_KEY="$1"
PRIMARY_IP="$2"
TOKEN_FILE="$3"

rm -f "$TOKEN_FILE"

echo "Waiting for RKE2 token from primary at $PRIMARY_IP..."

for i in {1..300}; do
  TOKEN=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" ubuntu@"$PRIMARY_IP" \
    'sudo cat /var/lib/rancher/rke2/server/node-token 2>/dev/null' 2>/dev/null || echo "")
  
  if [ -n "$TOKEN" ] && [ ${#TOKEN} -gt 10 ]; then
    echo "$TOKEN" > "$TOKEN_FILE"
    echo "✓ Token fetched at attempt $i (~$((i*2)) seconds)"
    exit 0
  fi
  
  if [ $((i % 30)) -eq 0 ] || [ $i -le 3 ]; then
    echo "  Attempt $i/300..."
  fi
  
  sleep 2
done

echo "✗ ERROR: Could not fetch token after 10 minutes"
exit 1
