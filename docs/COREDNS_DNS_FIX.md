# CoreDNS DNS Resolution Fix for Downstream Clusters

**Issue**: CoreDNS in the nprd-apps downstream cluster cannot resolve external domains like `rancher.dataknife.net`, preventing cluster registration with Rancher Manager.

## Root Cause

CoreDNS in RKE2 clusters needs to be explicitly configured to forward external DNS queries to upstream DNS servers. The `cloud-init-rke2.sh` script includes code to patch CoreDNS (lines 312-349), but:

1. **The patching only runs on server nodes** during initial provisioning
2. **The patching may fail silently** if CoreDNS isn't ready when the script runs
3. **The patching may not have run** if the cluster was provisioned differently

Without the `forward` directive in CoreDNS configuration, pods can only resolve:
- Kubernetes internal services (`*.cluster.local`)
- Pod IPs and service IPs

They **cannot** resolve external domains like `rancher.dataknife.net`.

## Quick Diagnosis

Check if CoreDNS is properly configured:

```bash
# Option 1: Use the diagnostic script
./scripts/check-coredns-config.sh nprd-apps

# Option 2: Manual check via SSH
ssh ubuntu@192.168.14.110  # or your nprd-apps server node IP
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
  get configmap rke2-coredns-rke2-coredns -n kube-system -o yaml | grep -A 20 Corefile
```

**Look for**: A line containing `forward  .` followed by DNS server IPs (e.g., `forward  . 192.168.1.1 1.1.1.1`)

**If missing**: CoreDNS is not forwarding external DNS queries.

## Quick Fix

### Option 1: Use the Fix Script (Recommended)

```bash
# Fix CoreDNS on nprd-apps cluster
./scripts/fix-coredns-dns.sh nprd-apps ubuntu ~/.ssh/id_rsa "192.168.1.1 1.1.1.1"

# Or if your DNS servers are different:
./scripts/fix-coredns-dns.sh nprd-apps ubuntu ~/.ssh/id_rsa "YOUR_DNS_IP 1.1.1.1"
```

The script will:
1. Connect to the first server node
2. Patch the CoreDNS ConfigMap with proper DNS forwarding
3. Restart CoreDNS pods to apply the configuration
4. Test DNS resolution

### Option 2: Manual Fix via SSH

```bash
# SSH to any server node in the nprd-apps cluster
ssh ubuntu@192.168.14.110  # Replace with your actual server node IP

# Set up environment
export PATH="/var/lib/rancher/rke2/bin:$PATH"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Patch CoreDNS ConfigMap
kubectl patch configmap rke2-coredns-rke2-coredns -n kube-system -p '{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health {\n        lameduck 10s\n    }\n    ready\n    kubernetes  cluster.local  cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    prometheus  0.0.0.0:9153\n    forward  . 192.168.1.1 1.1.1.1\n    cache  30\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'

# Restart CoreDNS pods
kubectl rollout restart deployment/rke2-coredns-rke2-coredns -n kube-system
```

**Note**: Replace `192.168.1.1 1.1.1.1` with your actual DNS servers if different.

## Verify the Fix

### Test DNS Resolution from a Pod

```bash
# Switch to nprd-apps cluster context
kubectl config use-context nprd-apps

# Create a test pod
kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net

# Expected output:
# Server:    10.43.0.10
# Address 1: 10.43.0.10
#
# Name:      rancher.dataknife.net
# Address 1: 192.168.14.100  # or your Rancher IP
```

### Check CoreDNS Configuration

```bash
kubectl get configmap rke2-coredns-rke2-coredns -n kube-system -o yaml | grep -A 20 Corefile
```

You should see:
```
forward  . 192.168.1.1 1.1.1.1
```

### Check cattle-cluster-agent Pods

After fixing DNS, the cattle-cluster-agent pods should be able to connect to Rancher:

```bash
kubectl get pods -n cattle-system
kubectl logs -n cattle-system -l app=cattle-cluster-agent --tail=50
```

Look for successful connection messages instead of DNS resolution errors.

## DNS Server Configuration

The fix script defaults to `192.168.1.1 1.1.1.1`, but you may need different DNS servers:

- **Local DNS/Gateway**: Usually your network gateway (e.g., `192.168.1.1`, `192.168.14.1`)
- **Fallback DNS**: Public DNS like `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google)

To determine your DNS servers:

```bash
# Check DNS servers configured on the node
ssh ubuntu@192.168.14.110
cat /etc/resolv.conf
# Look for "nameserver" lines
```

## Why This Happens

1. **RKE2 Default Behavior**: CoreDNS in RKE2 is configured to only resolve Kubernetes internal domains by default
2. **Cloud-Init Timing**: The patching script in `cloud-init-rke2.sh` may run before CoreDNS is ready
3. **Silent Failures**: The patching may fail silently if kubectl isn't available or CoreDNS deployment doesn't exist yet
4. **Different Provisioning**: If clusters were provisioned using different methods, the patching may not have run

## Prevention

To prevent this issue in future deployments:

1. **Verify CoreDNS Configuration**: After cluster provisioning, always verify CoreDNS has the `forward` directive
2. **Monitor cattle-cluster-agent Logs**: Check for DNS resolution errors during cluster registration
3. **Automated Testing**: Add DNS resolution tests to your deployment validation

## Related Documentation

- [DNS_RESOLUTION_FIX.md](DNS_RESOLUTION_FIX.md) - Original DNS resolution fix documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
- [RANCHER_DOWNSTREAM_MANAGEMENT.md](RANCHER_DOWNSTREAM_MANAGEMENT.md) - Downstream cluster management

## Scripts

- `scripts/fix-coredns-dns.sh` - Automated fix script
- `scripts/check-coredns-config.sh` - Diagnostic script to check CoreDNS configuration
