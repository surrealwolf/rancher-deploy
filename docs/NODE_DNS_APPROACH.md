# Node DNS Configuration Approach

## Overview

Instead of patching CoreDNS ConfigMap, we configure DNS at the node level by:
1. Disabling `systemd-resolved`
2. Configuring `/etc/resolv.conf` directly with DNS servers
3. CoreDNS pods automatically inherit `/etc/resolv.conf` from the node

This is simpler and more maintainable than patching CoreDNS ConfigMap.

## Benefits

1. **Single Source of Truth**: DNS configuration is managed at the node level
2. **Consistency**: All pods (including CoreDNS) inherit the same DNS configuration
3. **Maintainability**: Change DNS servers in one place (Terraform variables) instead of multiple locations
4. **Flexibility**: DNS servers can be different per environment/cluster via Terraform variables

## Implementation

### 1. Node DNS Configuration (cloud-init)

**Location**: `terraform/modules/proxmox_vm/cloud-init-rke2.sh`

DNS servers are configured directly in `/etc/resolv.conf` and `systemd-resolved` is disabled:

```bash
# Get DNS servers from environment or use defaults
DNS_SERVERS="${DNS_SERVERS:-192.168.1.1 1.1.1.1}"

# Stop and disable systemd-resolved
systemctl stop systemd-resolved
systemctl disable systemd-resolved

# Configure /etc/resolv.conf directly
cat > /etc/resolv.conf <<EOF
nameserver 192.168.1.1
nameserver 1.1.1.1
options edns0
EOF

# Make resolv.conf immutable to prevent overwrites
chattr +i /etc/resolv.conf
```

**DNS servers are passed from Terraform**:
- Terraform variable: `var.dns_servers` (list of DNS server IPs)
- Environment variable: `DNS_SERVERS` (space-separated string)
- Default: `192.168.1.1 1.1.1.1`

### 2. CoreDNS Automatic Inheritance

**CoreDNS pods automatically inherit `/etc/resolv.conf` from the node**:
- No CoreDNS ConfigMap patching needed
- No post-deployment scripts needed
- CoreDNS uses node DNS configuration automatically

**How it works**:
- Kubernetes mounts `/etc/resolv.conf` from the node into each pod
- CoreDNS pods read DNS servers from `/etc/resolv.conf`
- CoreDNS forwards external queries to the DNS servers listed in `/etc/resolv.conf`

## DNS Server Flow

```
Terraform Variables (dns_servers)
    ↓
Cloud-init (disable systemd-resolved, configure /etc/resolv.conf)
    ↓
/etc/resolv.conf (direct DNS server configuration)
    ↓
CoreDNS pods (/etc/resolv.conf inherited from node)
    ↓
Application pods (query CoreDNS, which uses node DNS)
```

## Configuration Points

### Terraform Variables

**Root level**: `terraform/variables.tf`
```hcl
variable "clusters" {
  type = map(object({
    dns_servers = list(string)
    # ...
  }))
}
```

**Module level**: `terraform/modules/proxmox_vm/variables.tf`
```hcl
variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["192.168.1.1", "1.1.1.1"]
}
```

**Usage**: `terraform/terraform.tfvars`
```hcl
clusters = {
  manager = {
    dns_servers = ["192.168.1.1", "1.1.1.1"]
    # ...
  }
  nprd-apps = {
    dns_servers = ["192.168.1.1", "1.1.1.1"]
    # ...
  }
}
```

### Environment-Specific Overrides

**Location**: `terraform/environments/*/terraform.tfvars`

```hcl
clusters = {
  manager = {
    dns_servers = ["192.168.1.1", "1.1.1.1"]  # Local DNS + Cloudflare
  }
}
```

## Verification

### Check Node DNS Configuration

```bash
# Check systemd-resolved status
resolvectl status

# Check /etc/resolv.conf
cat /etc/resolv.conf

# Check systemd-resolved config
cat /etc/systemd/resolved.conf.d/dns-servers.conf
```

### Check CoreDNS Configuration

```bash
# Check CoreDNS ConfigMap
kubectl get configmap rke2-coredns-rke2-coredns -n kube-system -o jsonpath='{.data.Corefile}'

# Check CoreDNS pod DNS
kubectl exec -n kube-system <coredns-pod> -- cat /etc/resolv.conf

# Test DNS resolution from a pod
kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net
```

## Migration Notes

### What Changed

1. **Before**: DNS servers hardcoded in CoreDNS ConfigMap patching (`192.168.1.1 1.1.1.1`)
2. **After**: DNS servers configured at node level, CoreDNS reads from node

### Backward Compatibility

- Existing clusters will continue to work (CoreDNS ConfigMap already patched)
- New clusters will use node DNS configuration
- Post-deployment scripts will update CoreDNS if DNS servers change

### Rollback

If needed, you can revert to hardcoded DNS by:
1. Removing systemd-resolved configuration from cloud-init
2. Restoring hardcoded DNS servers in CoreDNS patching

## Troubleshooting

### DNS Not Working

1. **Check node DNS**:
   ```bash
   resolvectl status
   ```

2. **Check CoreDNS ConfigMap**:
   ```bash
   kubectl get configmap rke2-coredns-rke2-coredns -n kube-system -o yaml
   ```

3. **Check CoreDNS logs**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=rke2-coredns-rke2-coredns
   ```

4. **Test DNS from node**:
   ```bash
   dig @192.168.1.1 rancher.dataknife.net
   ```

5. **Test DNS from pod**:
   ```bash
   kubectl run -it --rm --restart=Never --image=busybox dns-test -- nslookup rancher.dataknife.net
   ```

### DNS Servers Not Applied

1. Check cloud-init logs:
   ```bash
   cat /var/log/rke2-install.log | grep -i dns
   ```

2. Check systemd-resolved status:
   ```bash
   systemctl status systemd-resolved
   ```

3. Manually restart systemd-resolved:
   ```bash
   sudo systemctl restart systemd-resolved
   ```

## Related Documentation

- [COREDNS_DNS_FIX.md](COREDNS_DNS_FIX.md) - Original CoreDNS DNS forwarding fix
- [TERRAFORM_APPLY_ISSUES.md](TERRAFORM_APPLY_ISSUES.md) - Terraform apply issues and fixes
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
