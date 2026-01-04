#!/bin/bash
# Check cattle-cluster-agent status and troubleshoot DNS issues

set -e

PRIMARY_IP="${1:-192.168.14.110}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-ubuntu}"

KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml"

echo "=========================================="
echo "Checking cattle-cluster-agent Status"
echo "=========================================="
echo ""

# Check agent pod status
echo "[1] Agent Pod Status:"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
  "$KUBECTL get pods -n cattle-system -l app=cattle-cluster-agent -o wide" 2>&1
echo ""

# Check agent logs
echo "[2] Agent Logs (last 30 lines):"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
  "$KUBECTL logs -n cattle-system -l app=cattle-cluster-agent --tail=30" 2>&1 || echo "  (Pod may not be running yet)"
echo ""

# Check DNS resolution from a test pod
echo "[3] Testing DNS Resolution:"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
  "$KUBECTL run dns-check-\$(date +%s) --image=busybox --restart=Never --rm -i -- nslookup rancher.dataknife.net 2>&1" | head -15 || echo "  DNS test failed"
echo ""

# Check CoreDNS status
echo "[4] CoreDNS Pods:"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
  "$KUBECTL get pods -n kube-system | grep coredns" 2>&1
echo ""

# Check CoreDNS config
echo "[5] CoreDNS Forward Configuration:"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$PRIMARY_IP" \
  "$KUBECTL get configmap rke2-coredns-rke2-coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep -A 2 forward" 2>&1
echo ""

echo "=========================================="
echo "Status Check Complete"
echo "=========================================="
