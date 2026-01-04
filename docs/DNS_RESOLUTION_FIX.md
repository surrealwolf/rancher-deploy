# DNS Resolution Fix for RKE2 CoreDNS

**Date**: January 4, 2026  
**Status**: ✅ Implemented for both manager and apps clusters  
**Scope**: All RKE2 clusters deployed via Terraform

## Problem

RKE2 clusters were unable to resolve external DNS names (e.g., `rancher.dataknife.net`). Pods using Kubernetes DNS (CoreDNS) would fail to resolve external domains, even though the host nodes had proper DNS configuration.

**Root Cause**: CoreDNS was configured to only use Kubernetes internal DNS without proper forwarding configuration for external domains.

**Symptom**: 
```
ERROR: https://rancher.dataknife.net/ping is not accessible 
(Could not resolve host: rancher.dataknife.net)
```

## Solution

Updated RKE2 installation to configure proper DNS forwarding at two levels:

### 1. Kubelet Configuration (DNS Arguments)

Added explicit DNS configuration to RKE2 config files for all server nodes:

```yaml
kubelet-arg:
  - "cluster-dns=10.43.0.10"
  - "cluster-domain=cluster.local"
```

**Location**: `/etc/rancher/rke2/config.yaml` (created during RKE2 installation)  
**Applied to**: All RKE2 server nodes (both manager and apps clusters)

### 2. CoreDNS ConfigMap Patching

After RKE2 starts, the installation script patches CoreDNS to explicitly forward external DNS queries:

```
forward  . 192.168.1.1 1.1.1.1
```

**Upstream DNS Servers**:
- **Primary**: `192.168.1.1` (Local UniFi DNS - manages internal domains like `*.dataknife.net`)
- **Fallback**: `1.1.1.1` (Cloudflare public DNS - for general internet resolution)

**Location**: CoreDNS ConfigMap in `kube-system` namespace  
**Applied to**: Cluster-wide (all CoreDNS pods automatically use updated config)

## Implementation Details

**File Modified**: `terraform/modules/proxmox_vm/cloud-init-rke2.sh`

### Changes Made:

#### 1. RKE2 Config File Updates (Lines ~215 & ~240)

**For Primary Server Nodes:**
```bash
cat > /etc/rancher/rke2/config.yaml <<EOF
# Primary RKE2 server with HA etcd clustering
tls-san:
  - ${CLUSTER_HOSTNAME}
  - ${CLUSTER_PRIMARY_IP}

# DNS configuration - allow CoreDNS to forward external queries
kubelet-arg:
  - "cluster-dns=10.43.0.10"
  - "cluster-domain=cluster.local"
EOF
```

**For Secondary Server Nodes:**
```bash
cat > /etc/rancher/rke2/config.yaml <<EOF
# Secondary RKE2 server - join primary cluster via shared etcd
server: https://SERVER_IP_PLACEHOLDER:9345
token: SERVER_TOKEN_PLACEHOLDER
tls-san:
  - ${CLUSTER_HOSTNAME}
  - ${CLUSTER_PRIMARY_IP}

# DNS configuration - allow CoreDNS to forward external queries
kubelet-arg:
  - "cluster-dns=10.43.0.10"
  - "cluster-domain=cluster.local"
EOF
```

#### 2. CoreDNS ConfigMap Patching (Lines ~310-360)

After RKE2 service starts:

```bash
# Wait for CoreDNS to be ready (max 120 seconds)
# Patch CoreDNS ConfigMap with explicit upstream DNS forwarding
kubectl patch configmap rke2-coredns-rke2-coredns -n kube-system -p '{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health {\n        lameduck 10s\n    }\n    ready\n    kubernetes  cluster.local  cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    prometheus  0.0.0.0:9153\n    forward  . 192.168.1.1 1.1.1.1\n    cache  30\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'

# Restart CoreDNS pods to apply new configuration
kubectl rollout restart deployment/rke2-coredns-rke2-coredns -n kube-system
```

## Cluster Coverage

✅ **Manager Cluster (401-403)**
- All nodes configured with DNS kubelet-args
- Primary node (401) patches CoreDNS for cluster-wide DNS resolution
- Secondary nodes (402-403) inherit CoreDNS configuration

✅ **Apps Cluster (404-406)**
- All nodes configured with DNS kubelet-args  
- Primary node (404) patches CoreDNS for cluster-wide DNS resolution
- Secondary nodes (405-406) inherit CoreDNS configuration

**Implementation**: Both clusters use the same `cloud-init-rke2.sh` provisioning script, so both get identical DNS configuration.

## Verification

### Check CoreDNS Configuration

```bash
# Verify CoreDNS ConfigMap has the forward directive
kubectl get configmap -n kube-system rke2-coredns-rke2-coredns -o yaml | grep -A 20 "Corefile"

# Should show:
# forward  . 192.168.1.1 1.1.1.1
```

### Test DNS Resolution

```bash
# Test from a pod in the cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup rancher.dataknife.net

# Should resolve to:
# Name:      rancher.dataknife.net
# Address 1: 192.168.14.100 manager.dataknife.net
```

### Verify Pod Can Reach Rancher

```bash
# For cattle-cluster-agent in apps cluster
kubectl logs -n cattle-system -l app=cattle-cluster-agent | grep -E "INFO.*https://rancher|ERROR"

# Should show successful connection attempts without DNS errors
```

## DNS Resolution Flow

```
Pod DNS Query
    ↓
CoreDNS Service (10.43.0.10:53)
    ↓
Check Kubernetes Internal (cluster.local, etc.)
    ↓ (Not found, fallthrough)
Forward to Upstream: 192.168.1.1, 1.1.1.1
    ↓
Local DNS (192.168.1.1) resolves rancher.dataknife.net → 192.168.14.100
    ↓
Pod receives answer
```

## Future Improvements

1. **Make DNS Servers Configurable**: Extract DNS servers from terraform variables instead of hardcoding
2. **CoreDNS Custom Plugin**: Consider using CoreDNS `/etc/hosts` plugin for persistent local records
3. **DNS Failover Testing**: Implement automated tests to verify DNS failover to fallback server
4. **Metrics**: Add PrometheusRules to monitor DNS query patterns and failures

## References

- [CoreDNS Configuration](https://coredns.io/plugins/forward/)
- [RKE2 Kubelet Arguments](https://docs.rke2.io/install/configuration/#kubelet-arguments)
- [Kubernetes DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## Related Documentation

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Full deployment walkthrough
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
