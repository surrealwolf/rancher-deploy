# Downstream Cluster Registration - Technical Findings

**Date**: January 4, 2026  
**Status**: ✅ **RESOLVED** - Manifest-based approach implemented and verified  

## Problem Statement

The initial system-agent-install.sh approach for registering downstream RKE2 clusters with Rancher Manager was failing with timeout errors:

```
ERROR: https://rancher.example.com/ping is not accessible
curl: (28) Operation timed out after 60002 milliseconds with 0 bytes received
```

## Root Cause Analysis

**System-Agent Approach Bottleneck:**
The RKE2 system-agent-install.sh script attempts to reach the Rancher API endpoint:
```
/v3/connect/agent
```

This endpoint:
- ❌ Does not respond from external/downstream cluster nodes
- ❌ Hangs indefinitely after 60 seconds with no response
- ❌ Is intended for internal agent communication, not node registration
- ❌ Causes complete script timeout without fallback mechanism

The script flow:
```
1. Download system-agent-install.sh from Rancher ✅
2. Execute script with cluster registration token ✅
3. Script calls retrieve_connection_info() ⚠️
4. Function makes GET request to /v3/connect/agent endpoint ❌
5. Endpoint times out / no response
6. Script fails after 60 second timeout
7. No registration occurs
```

## Solution: Manifest-Based Registration

Instead of downloading and executing the system-agent-install.sh script, we discovered that Rancher provides a **direct Kubernetes manifest** via the `/v3/import/{token}_{cluster-id}.yaml` endpoint.

### How It Works

**Step 1: Get Registration Token**
```bash
curl -H "Authorization: Bearer $API_TOKEN" \
  https://rancher.example.com/v3/clusters/$CLUSTER_ID/clusterregistrationtokens
```
Returns: Token ID and token value

**Step 2: Fetch Manifest**
```bash
curl https://rancher.example.com/v3/import/$TOKEN_VALUE_$CLUSTER_ID.yaml
```
Returns: Complete Kubernetes manifest (YAML)

**Step 3: Apply Manifest**
```bash
kubectl apply -f manifest.yaml
```
Creates:
- Namespace: `cattle-system`
- ServiceAccount: `cattle`
- Secret: `cattle-credentials` (with token, URL, CA cert)
- ClusterRole & ClusterRoleBinding
- Deployment: `cattle-cluster-agent`
- Service: for pod discovery

**Step 4: Automatic Registration**
- Pods start automatically from deployment
- cattle-cluster-agent reads credentials from secret
- Pods connect to Rancher Manager API
- Cluster automatically registers without manual steps

### Manifest Contents Example

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cattle
  namespace: cattle-system
---
apiVersion: v1
kind: Secret
metadata:
  name: cattle-credentials-<hash>
  namespace: cattle-system
data:
  token: <base64 encoded token>
  url: <base64 encoded rancher url>
  namespace: <base64 encoded namespace>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cattle-cluster-agent
  namespace: cattle-system
spec:
  selector:
    matchLabels:
      app: cattle-cluster-agent
  template:
    metadata:
      labels:
        app: cattle-cluster-agent
    spec:
      containers:
      - image: docker.io/rancher/rancher-agent:v2.13.1
        name: cluster-register
        env:
        - name: CATTLE_SERVER
          value: https://rancher.example.com
        - name: CATTLE_TOKEN
          valueFrom:
            secretKeyRef:
              name: cattle-credentials-<hash>
              key: token
        - name: CATTLE_CA_CHECKSUM
          value: <certificate hash>
        - name: CATTLE_CLUSTER
          value: "true"
        # ... additional environment variables
---
# Additional RBAC resources for cluster communication
```

## Comparison: Old vs. New Approach

### System-Agent-Install.sh (OLD)
| Aspect | Status |
|--------|--------|
| **Reliability** | ❌ Hangs on `/v3/connect/agent` |
| **Speed** | ❌ 60+ second timeout |
| **Dependencies** | ⚠️ Requires downloading external script |
| **Network-friendly** | ❌ Needs direct access to script download |
| **Automation** | ⚠️ Error handling unclear |
| **Debugging** | ❌ Limited error messages |

### Manifest-Based Approach (NEW)
| Aspect | Status |
|--------|--------|
| **Reliability** | ✅ Direct API endpoints, no hangs |
| **Speed** | ✅ 2-3 minutes for full registration |
| **Dependencies** | ✅ Just curl + kubectl (commonly available) |
| **Network-friendly** | ✅ Only needs Rancher API access |
| **Automation** | ✅ Clear success/failure |
| **Debugging** | ✅ kubectl logs provide full visibility |

## Implementation Details

### Terraform Module
**Location**: `terraform/modules/rancher_downstream_registration/main.tf`

**Key Features**:
- Fetches registration token from Rancher API
- Constructs manifest URL with token
- Applies manifest to all downstream nodes via SSH + kubectl
- No external script downloads needed
- Idempotent: safe to run multiple times

**Inputs**:
- `rancher_url`: Rancher Manager API endpoint
- `rancher_token_file`: Path to API token
- `cluster_id`: Downstream cluster ID
- `cluster_nodes`: Map of node IPs
- `ssh_private_key_path`: Private key for SSH access

**Process**:
```
1. Read Rancher API token
2. Fetch or create registration token
3. Download manifest from API
4. For each node:
   a. SSH into node
   b. curl manifest from Rancher
   c. Pipe to kubectl apply
5. Verify pods are created
```

## Verification Steps

### Check Manifest Applied Successfully
```bash
kubectl -n cattle-system get pods -l app=cattle-cluster-agent
# Expected: cattle-cluster-agent pods in Running state
```

### Check Pod Logs
```bash
kubectl -n cattle-system logs cattle-cluster-agent-<pod-hash>
# Should show: Connecting to Rancher, Registration successful
```

### Verify in Rancher Manager
```bash
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get clusters.management.cattle.io <cluster-id>
kubectl describe clusters.management.cattle.io <cluster-id>
```

### Check Agent Connection
```bash
kubectl -n cattle-system get deployment cattle-cluster-agent -o yaml
# Verify image and environment variables are correct
```

## Testing Results (Jan 4, 2026)

### Test Environment
- Rancher Manager: v2.13.1 on 3-node RKE2 cluster
- NPRD Apps Cluster: 3-node RKE2 (v1.34.3+rke2r1)
- Network: Isolated lab environment with self-signed certs

### Test Results
✅ **Manifest fetched successfully** from `/v3/import/{token}.yaml`  
✅ **Applied to all 3 nodes** without errors  
✅ **RBAC created** correctly (ClusterRole, ClusterRoleBinding)  
✅ **ServiceAccount created** in cattle-system namespace  
✅ **Secret created** with proper credentials  
✅ **Deployment created** with cattle-cluster-agent image  
✅ **Pods started successfully** on all nodes  
✅ **Pods registered** with Rancher Manager  
✅ **Cluster visible** in Rancher UI within 2-3 minutes  
✅ **Node status** showing as Ready in both clusters  

### Performance Metrics
- Manifest download: ~1-2 seconds
- Application to 3 nodes: ~10-15 seconds per node
- Pod startup: ~30-60 seconds
- **Total registration time: 2-3 minutes** (vs. 60+ second timeout with old method)

### Pod Status After Registration
```
NAMESPACE      NAME                             READY   STATUS    RESTARTS
cattle-system  cattle-cluster-agent-868...      1/1     Running   0
cattle-system  rancher-webhook-...              1/1     Running   0
cattle-system  system-upgrade-controller-...    1/1     Running   0
```

## Known Limitations & Edge Cases

### 1. CA Certificate Verification
**Issue**: Rancher uses self-signed certificate  
**Solution**: Manifest includes `CATTLE_CA_CHECKSUM` for verification  
**Status**: ✅ Resolved by Rancher manifest

### 2. Network Isolation
**Issue**: Pods need to reach Rancher API endpoint  
**Solution**: DNS must be configured correctly, network path must be open  
**Verification**: 
```bash
nslookup rancher.example.com
curl -sk https://rancher.example.com/health
```

### 3. RBAC Permissions
**Issue**: Pods need permission to create resources  
**Solution**: Manifest includes proper RBAC definitions  
**Status**: ✅ ClusterRole grants necessary permissions

### 4. Token Expiration
**Issue**: Registration tokens may expire  
**Solution**: Terraform creates new tokens as needed  
**Status**: ✅ Automatic token refresh

## Migration Path

For users with existing deployments using system-agent-install.sh:

1. **Disable old module** in terraform (comment out or set count=0)
2. **Enable new module** in terraform (rancher_downstream_registration)
3. **Re-apply terraform** (safe, idempotent)
4. **Verify pods** appear in cattle-system namespace
5. **Clean up** old system-agent pods (if any remain)

## Recommendations

### For Production Deployments
1. ✅ Use manifest-based registration (default in current version)
2. ✅ Verify DNS resolution before deployment
3. ✅ Ensure Rancher API is accessible from all cluster nodes
4. ✅ Monitor cattle-cluster-agent pods during registration
5. ✅ Test failover scenarios (pod restart, node failure)

### For Network-Restricted Environments
1. ✅ Pre-cache Rancher agent image in private registry
2. ✅ Configure image pull secrets if needed
3. ✅ Verify outbound HTTPS is allowed to Rancher API
4. ✅ Consider air-gapped Rancher setup if no external access

### For Debugging
1. ✅ Check pod logs: `kubectl logs -n cattle-system <pod-name>`
2. ✅ Check events: `kubectl get events -n cattle-system`
3. ✅ Verify manifest: `kubectl get all -n cattle-system`
4. ✅ Test connectivity: `curl -sk https://rancher.example.com/health`

## References

- **Rancher Docs**: https://ranchermanager.docs.rancher.com/
- **RKE2 Docs**: https://docs.rke2.io/
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **manifests API**: `/v3/import/{token}_{cluster-id}.yaml`
- **Token API**: `/v3/clusters/{cluster-id}/clusterregistrationtokens`

## Timeline

| Date | Event |
|------|-------|
| Jan 3, 2026 | Initial system-agent approach deployment |
| Jan 3, 2026 (evening) | Timeout issues discovered |
| Jan 4, 2026 (morning) | Root cause analysis: `/v3/connect/agent` endpoint issue |
| Jan 4, 2026 (midday) | Discovery: manifestUrl endpoint with direct YAML |
| Jan 4, 2026 (afternoon) | Manual testing: Successfully applied manifest to 3 nodes |
| Jan 4, 2026 (late afternoon) | cattle-cluster-agent pods fully operational |
| Jan 4, 2026 (evening) | Terraform module updated, documentation revised |

## Conclusion

The shift from system-agent-install.sh to manifest-based registration represents a **significant improvement in reliability, simplicity, and maintainability**. The new approach:

- ✅ Eliminates timeout issues
- ✅ Simplifies the registration process
- ✅ Provides better debugging visibility
- ✅ Works in more network environments
- ✅ Maintains full automation without manual UI steps

The implementation is **production-ready** and **thoroughly tested** in the lab environment.
