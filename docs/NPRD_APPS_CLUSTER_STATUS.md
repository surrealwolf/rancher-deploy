# NPRD-Apps Cluster Registration Status

**Date**: January 4, 2026  
**Cluster**: nprd-apps (c-j8zdc)  
**Status**: ⚠️ **PENDING** - DNS resolution intermittent, registration incomplete

## Current Status

### Cluster State
- **Rancher Cluster ID**: `c-j8zdc`
- **State**: Pending
- **Connected**: False
- **Waiting**: "Waiting for API to be available"

### DNS Resolution Status

**CoreDNS Configuration**: ✅ Configured
- Forward directive present: `forward  . 192.168.1.1 1.1.1.1`
- Cache TTL: Reduced to 5 seconds (from 30) to minimize negative cache issues

**DNS Resolution**: ⚠️ **Intermittent**
- ✅ `dig @10.43.0.10 rancher.dataknife.net` - **Works consistently**
- ⚠️ `nslookup` from pods - **Intermittent failures**
- ⚠️ Agent pod DNS queries - **Mix of successes and failures**

**Observed Behavior**:
- First query often fails with NXDOMAIN
- Subsequent queries succeed
- Suggests CoreDNS negative caching or timing issues

### Agent Pod Status

**Pod**: `cattle-cluster-agent-58dd8b8bfd-*`
- **Status**: Running
- **DNS Policy**: ClusterFirst (correct)
- **DNS Server**: 10.43.0.10 (CoreDNS service)

**Log Patterns**:
1. **DNS Resolution Errors** (intermittent):
   ```
   error="dial tcp: lookup rancher.dataknife.net on 10.43.0.10:53: no such host"
   ```

2. **Registration Errors** (when DNS works):
   ```
   error="websocket: bad handshake"
   Response body: cluster not found
   ```

## Root Cause Analysis

### Issue 1: Intermittent DNS Resolution

**Symptoms**:
- CoreDNS ConfigMap is correctly configured with forward directive
- `dig` queries work consistently
- `nslookup` from pods fails intermittently
- Agent pod experiences DNS failures ~50% of the time

**Possible Causes**:
1. **CoreDNS Negative Caching**: Failed queries are cached, causing subsequent failures
2. **Timing Issues**: CoreDNS pods may not have fully reloaded configuration
3. **Network Policy**: Pods may have restricted egress to DNS servers
4. **Forward Plugin Behavior**: May need additional configuration for reliability

**Fixes Applied**:
- ✅ Reduced cache TTL from 30 to 5 seconds
- ✅ Restarted CoreDNS pods multiple times
- ✅ Verified forward directive is present

**Remaining Issues**:
- DNS resolution still intermittent
- May need to investigate CoreDNS forward plugin configuration
- May need to check network policies or pod security policies

### Issue 2: "Cluster Not Found" Registration Error

**Symptoms**:
- When DNS resolves, agent connects to Rancher
- Receives "400 Bad Request - cluster not found" error
- Suggests cluster registration token or cluster ID mismatch

**Possible Causes**:
1. **Cluster ID Mismatch**: Token was created for different cluster ID
2. **Token Expiration**: Registration token may have expired
3. **Cluster Deleted/Recreated**: Cluster object may have been recreated with new ID
4. **Registration Manifest Issue**: Manifest may reference wrong cluster ID

**Investigation Needed**:
- Verify cluster ID matches between Rancher and registration manifest
- Check registration token validity
- Verify cluster object exists in Rancher Manager

## Verification Steps

### Check DNS Resolution
```bash
# From nprd-apps cluster node
ssh ubuntu@192.168.14.110
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
  run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net

# Test multiple times to check consistency
for i in {1..5}; do
  sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
    run -it --rm --restart=Never --image=busybox dns-test-$i -- nslookup rancher.dataknife.net
  sleep 2
done
```

### Check Agent Pod Logs
```bash
ssh ubuntu@192.168.14.110
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
  logs -n cattle-system -l app=cattle-cluster-agent --tail=50
```

### Check Cluster Registration
```bash
# From manager cluster
ssh ubuntu@192.168.14.100
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
  get clusters.management.cattle.io c-j8zdc -o yaml

# Check cluster conditions
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
  get clusters.management.cattle.io c-j8zdc -o jsonpath='{.status.conditions[*]}' | jq '.'
```

## Recommended Next Steps

### Immediate Actions

1. **Verify Cluster Registration Token**:
   - Check if cluster ID `c-j8zdc` exists in Rancher
   - Verify registration token matches cluster ID
   - Re-create registration token if needed

2. **Re-register Cluster**:
   - Delete existing cattle-cluster-agent deployment
   - Fetch new registration manifest from Rancher
   - Apply fresh manifest to cluster

3. **Investigate DNS Intermittency**:
   - Check CoreDNS pod logs for forward errors
   - Verify network connectivity from CoreDNS pods to 192.168.1.1:53
   - Consider adding `max_fails` and `health_check` to forward plugin

### Long-term Fixes

1. **Improve CoreDNS Forward Configuration**:
   ```yaml
   forward . 192.168.1.1 1.1.1.1 {
       max_fails 3
       health_check 5s
   }
   ```

2. **Add DNS Monitoring**:
   - Set up Prometheus alerts for DNS resolution failures
   - Monitor CoreDNS forward plugin metrics

3. **Document DNS Troubleshooting**:
   - Add to troubleshooting guide
   - Create runbook for DNS issues

## Related Documentation

- [DNS_RESOLUTION_FIX.md](DNS_RESOLUTION_FIX.md) - CoreDNS DNS forwarding configuration
- [COREDNS_DNS_FIX.md](COREDNS_DNS_FIX.md) - Manual CoreDNS fix procedures
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
- [RANCHER_DOWNSTREAM_MANAGEMENT.md](RANCHER_DOWNSTREAM_MANAGEMENT.md) - Cluster registration guide
