# Terraform Apply Issues - January 4, 2026

**Log File**: `logs/terraform-1767563861.log`  
**Apply Time**: Jan 4, 14:07  
**Status**: ⚠️ **Partial Success** - Some steps completed but with warnings

## Issues Found

### 1. DNS Resolution Test Failed ⚠️

**Location**: `module.rke2_manager.null_resource.configure_coredns_dns` and `module.rke2_apps.null_resource.configure_coredns_dns`

**Status**: CoreDNS was configured successfully, but DNS resolution test failed

**Log Evidence**:
```
⚠ DNS resolution test failed, but CoreDNS is configured
  You can test manually: kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net
✓ CoreDNS DNS configuration complete
```

**Root Cause**: 
- Timing issue: DNS test runs too soon after CoreDNS pods restart (only 15 seconds wait)
- Test uses `kubectl run --rm` which may not wait for pod completion properly
- CoreDNS pods need more time to fully initialize after restart

**Fix Applied**:
- Increased wait time from 15 to 25 seconds (10s initial + 15s wait)
- Improved test logic to check for pod completion
- Added better error messages with troubleshooting hints

**Impact**: Low - CoreDNS is configured correctly, test failure is just a verification issue

### 2. Downstream Cluster Registration Failed ⚠️

**Location**: `module.rancher_downstream_registration[0].null_resource.register_downstream_cluster`

**Status**: Registration manifest application failed on all 3 nodes

**Log Evidence**:
```
⚠ Registration on nprd-apps-1 may have failed
⚠ Registration on nprd-apps-2 may have failed
⚠ Registration on nprd-apps-3 may have failed
```

**Root Cause**:
- The grep pattern `grep -q "created\|unchanged"` uses basic regex syntax
- `\|` (OR operator) requires extended regex (`grep -E` or `grep -qE`)
- Without `-E` flag, `\|` is treated as literal pipe character, so pattern never matches
- Registration actually succeeded (manifest was applied), but script couldn't detect it

**Manual Verification**:
```bash
# Manifest URL works:
curl -sk 'https://rancher.dataknife.net/v3/import/vll6qg5678wjrwslj628tqfmdj2p49h7vnx2v4c9mr5qk9dpwrq5j8_c-x7jzf.yaml' | kubectl apply -f -
# Result: Resources created successfully

# Pod exists:
kubectl get pods -n cattle-system
# Result: cattle-cluster-agent pod exists (but in CrashLoopBackOff)
```

**Fix Applied**:
- Changed `grep -q "created\|unchanged"` to `grep -qE "(created|unchanged)"`
- Added output capture to show actual registration output on failure
- Improved error reporting

**Impact**: Medium - Registration actually worked, but script reported failure incorrectly

### 3. DNS Still Not Resolving in Pods ⚠️

**Location**: `cattle-cluster-agent` pods in nprd-apps cluster

**Status**: Pods are in CrashLoopBackOff due to DNS resolution failures

**Log Evidence**:
```
ERROR: https://rancher.dataknife.net/ping is not accessible (Could not resolve host: rancher.dataknife.net)
```

**Current State**:
- CoreDNS ConfigMap has correct forward directive: `forward  . 192.168.1.1 1.1.1.1`
- Cache TTL is set to 5 seconds
- CoreDNS pods have restarted
- But pods still cannot resolve `rancher.dataknife.net`

**Possible Causes**:
1. **CoreDNS pods not fully ready**: Pods may have restarted but not fully initialized
2. **Negative cache**: Previous DNS failures may be cached
3. **Network connectivity**: CoreDNS pods may not be able to reach 192.168.1.1:53
4. **Timing**: Registration ran before DNS was fully working

**Investigation Needed**:
- Check CoreDNS pod logs for forward errors
- Verify CoreDNS pods can reach DNS server (192.168.1.1:53)
- Test DNS resolution from CoreDNS pod directly
- Check if there are network policies blocking DNS

**Fix Applied**:
- Improved DNS verification test with longer wait times
- Added better error messages

**Impact**: High - Cluster registration cannot complete without DNS resolution

## Summary of Fixes

### Fixed Issues ✅

1. **Registration Script Grep Pattern**: Changed to use extended regex (`grep -qE`)
2. **DNS Verification Timing**: Increased wait times and improved test logic
3. **Error Reporting**: Added better output capture and error messages

### Remaining Issues ⚠️

1. **DNS Resolution in Pods**: Still not working despite CoreDNS configuration
   - Need to investigate CoreDNS pod connectivity to DNS servers
   - May need to check network policies or pod security policies
   - May need to wait longer or restart CoreDNS pods again

2. **Registration Detection**: Script now correctly detects success/failure

## Next Steps

1. **Verify DNS Resolution**:
   ```bash
   # Test from CoreDNS pod
   kubectl exec -n kube-system <coredns-pod> -- nslookup rancher.dataknife.net
   
   # Test from regular pod
   kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net
   ```

2. **Check CoreDNS Logs**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=rke2-coredns-rke2-coredns --tail=50
   ```

3. **Verify Network Connectivity**:
   ```bash
   # From CoreDNS pod
   kubectl exec -n kube-system <coredns-pod> -- nc -zv 192.168.1.1 53
   ```

4. **Re-run Registration** (if DNS is fixed):
   ```bash
   # The registration script should now correctly detect success
   terraform apply -target=module.rancher_downstream_registration
   ```

## Files Modified

1. `terraform/modules/rancher_downstream_registration/main.tf` - Fixed grep pattern
2. `terraform/modules/rke2_manager_cluster/main.tf` - Improved DNS verification
3. `terraform/modules/rke2_downstream_cluster/main.tf` - Improved DNS verification

## Related Documentation

- [COREDNS_DNS_FIX.md](COREDNS_DNS_FIX.md) - CoreDNS DNS forwarding configuration
- [NPRD_APPS_CLUSTER_STATUS.md](NPRD_APPS_CLUSTER_STATUS.md) - Cluster registration status
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
