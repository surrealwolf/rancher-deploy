# Rancher Downstream Cluster Management

**Last Updated**: January 3, 2026  
**Status**: ✅ **FULLY AUTOMATED** with Native Rancher2 Provider

This guide explains how to automatically register downstream (NPRD Apps) clusters with Rancher Manager using Terraform.

## Overview

The deployment now provides **end-to-end automated downstream cluster registration** using the native `rancher2` Terraform provider. When you set `register_downstream_cluster = true` in `terraform.tfvars`, the NPRD Apps cluster will:

1. Deploy 3 RKE2 nodes
2. Configure proper DNS servers  
3. Rancher automatically creates cluster object and extracts registration credentials
4. VMs automatically install Rancher system-agent
5. Cluster automatically registers with Rancher Manager
6. Nodes automatically download RKE2 components and become operational

**Total deployment time**: ~40-50 minutes (VMs + RKE2 + **automatic** Rancher registration)

**No manual Rancher UI steps required!** ✅

## Quick Start - Fully Automated

### 1. Configure Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
# Enable downstream cluster auto-registration (NATIVE METHOD)
register_downstream_cluster = true

# Rancher credentials (API token, can be generated manually or left empty)
# If empty, will use credentials from deploy-rancher.sh
rancher_api_token = ""  # Auto-created during Rancher deployment

# Rancher hostname (must match DNS and Rancher ingress)
rancher_hostname = "rancher.example.com"

# Ensure correct DNS servers (for internal name resolution)
clusters = {
  manager = {
    dns_servers = ["192.168.1.1", "1.1.1.1"]  # Local, Fallback
  }
  nprd-apps = {
    dns_servers = ["192.168.1.1", "1.1.1.1"]  # Local, Fallback
  }
}
```

### 2. Deploy Everything Automatically

```bash
cd terraform
./scripts/apply.sh -auto-approve

# Or manually
cd terraform
terraform apply -auto-approve
```

**What happens automatically (no manual steps):**
1. VMs created (2-3 min)
2. Cloud-init configures networking with proper DNS
3. RKE2 installed on all manager nodes (5-10 min)
4. Rancher deployed via Helm on manager cluster
5. **Rancher API token auto-created** and saved to `~/.kube/.rancher-api-token`
6. **Native rancher2 provider uses token** to create cluster object in Rancher
7. **Registration credentials auto-extracted** from Rancher API
8. RKE2 installed on all apps nodes (5-10 min)
9. Rancher system-agent auto-registers all apps nodes
10. **Cluster becomes fully operational** without any manual UI interaction

### 3. Verify Registration

Check Rancher UI → Cluster Management:
- Your cluster should appear as "Active"
- All 3 nodes should show as "Ready"
- Status should show "Active"

```bash
# Verify from kubectl
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get clusters.management.cattle.io

# Check the registered cluster details
kubectl describe clusters.management.cattle.io nprd-apps
```

## Implementation Details

### How Native Rancher2 Provider Works

The native `rancher2` Terraform provider automates the entire registration flow:

```hcl
# In terraform/main.tf:

resource "rancher2_cluster" "nprd_apps" {
  name           = "nprd-apps"
  description    = "NPRD Applications Cluster (Auto-Registered)"
  rke2_config {
    # Configuration...
  }
}

# This automatically:
# 1. Creates cluster object in Rancher
# 2. Extracts registration token and CA checksum
# 3. Makes them available to downstream VMs via cloud-init
# 4. VMs use credentials to self-register with Rancher
```

**Workflow:**
```
terraform apply
    ↓
1. rancher2_cluster resource created with API token from ~/.kube/.rancher-api-token
    ↓
2. Rancher API creates cluster object and returns registration credentials
    ↓
3. Credentials passed to RKE2 modules via cloud-init
    ↓
4. VMs download and execute registration script automatically
    ↓
5. System-agent registers each node with Rancher
    ↓
6. Cluster becomes operational (all nodes Ready, cluster Active)
```

**Key advantages of native provider approach:**
- ✅ **Zero Rancher UI steps** - Everything in Terraform code
- ✅ **Idempotent** - Safe to run `terraform apply` multiple times
- ✅ **Self-healing** - Tokens automatically refreshed if expired
- ✅ **GitOps-ready** - Full state tracked in Terraform state file
- ✅ **Scriptable** - No interactive clicking required

### Alternative: Manual Registration (Legacy)

If you prefer not to use the native provider, you can manually register the cluster. This requires extracting credentials from Rancher UI and updating Terraform variables.

**Status**: ⚠️ Still supported but not recommended

Requires manually obtaining registration token from Rancher UI and passing it to Terraform.

**Disadvantages:**
- ❌ Requires copy/paste of credentials from UI
- ❌ Token expires after 24 hours (need to regenerate)
- ❌ Extra manual steps (not fully automated)
- ❌ Not ideal for CI/CD

**When to use:**
- Registering existing clusters (not created by Terraform)
- Manual testing of registration flow
- Debugging registration issues

**Configuration:**
```hcl
# terraform/terraform.tfvars
register_downstream_cluster = true
rancher_registration_token = "pqmgbbjwm67nq5gtzlq54xvblqtx26b6t4sh89kczsvthdg9jn62h4"
rancher_ca_checksum        = "f97575101c793a8407b671c6dcc296867a25c23d286896fd95067955085aedd0"
rancher_api_token = ""  # Not needed for manual registration
```

**Time**: Same ~40-50 minutes (automatic registration happens same way)

## Configuration Details

### Option 1: Terraform rancher2 Provider Setup

**Step 1: Get Rancher API Token**

In Rancher Manager UI:
```
Account (top-right) → API Tokens → Create API Token
├─ Name: "terraform" (or any name)
├─ Description: "For downstream cluster creation"
└─ Copy token value: token-xxxxx:secret
```

**Step 2: Update terraform/terraform.tfvars**

```hcl
# Enable automatic downstream cluster creation via rancher2 provider
register_downstream_cluster = true

# Required: Rancher API token
rancher_api_token = "token-xxxxx:your-secret-token-here"

# These will be auto-generated from rancher2_cluster resource
rancher_registration_token = ""
rancher_ca_checksum        = ""
```

**Step 3: Deploy**

```bash
cd terraform
terraform init  # Downloads rancher2 provider
terraform apply -auto-approve
```

Terraform will:
1. Create cluster object in Rancher Manager
2. Extract registration credentials automatically
3. Pass to downstream VMs
4. VMs register themselves
5. Done! No manual steps.

### Option 2: Variables (Traditional)

Added to `terraform/variables.tf`:

```hcl
variable "register_downstream_cluster" {
  description = "Whether to automatically register downstream cluster with Rancher Manager"
  type        = bool
  default     = true  # Enabled by default
}

variable "rancher_registration_token" {
  description = "Token for downstream cluster registration (from Rancher UI)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rancher_ca_checksum" {
  description = "CA certificate checksum for HTTPS verification"
  type        = string
  default     = ""
}

variable "rancher_api_token" {
  description = "Rancher API token for automatic cluster creation (Option 1)"
  type        = string
  sensitive   = true
}
```

### DNS Configuration (Fixed)

Both manager and nprd-apps clusters now use **local DNS servers**:

```hcl
dns_servers = ["192.168.1.1", "1.1.1.1"]  # Local, Fallback
```

This enables:
- ✅ Resolution of `rancher.example.com` hostname
- ✅ Proper HTTPS certificate validation
- ✅ System-agent download and installation

### Provisioner Enhancement

The `proxmox_vm` module provisioner now conditionally adds:

1. **Hosts file entry** (if `register_with_rancher = true`):
   ```bash
   echo "192.168.1.100 rancher.example.com" | sudo tee -a /etc/hosts
   ```

2. **System-agent installation** (for primary node only):
   ```bash
   curl -kfL https://rancher.example.com/system-agent-install.sh | sudo sh -s - \
     --server https://rancher.example.com \
     --token <token> \
     --ca-checksum <checksum> \
     --etcd --controlplane --worker
   ```

### Terraform Resource Changes

**New rancher2_cluster resource in terraform/main.tf:**

```hcl
resource "rancher2_cluster" "nprd_apps" {
  count = var.register_downstream_cluster ? 1 : 0
  
  name                           = "nprd-apps"
  description                    = "Non-production applications cluster"
  enable_cluster_monitoring      = true
  
  depends_on = [
    module.rancher_deployment
  ]
}

# Extract token and CA checksum automatically
locals {
  nprd_registration_enabled = var.register_downstream_cluster && length(rancher2_cluster.nprd_apps) > 0
  nprd_registration_token   = local.nprd_registration_enabled ? rancher2_cluster.nprd_apps[0].cluster_registration_token[0].token : var.rancher_registration_token
  nprd_ca_checksum          = local.nprd_registration_enabled ? rancher2_cluster.nprd_apps[0].cluster_registration_token[0].ca_checksum : var.rancher_ca_checksum
}
```

This:
- ✅ Creates cluster object in Rancher Manager
- ✅ Automatically retrieves registration token and CA checksum
- ✅ Passes values to downstream VMs
- ✅ Falls back to variable values if manual registration preferred

### Deployment Flow

```
terraform apply
├─ Manager cluster deployment (10-15 min)
│  ├─ Create 3 VMs (401-403)
│  ├─ Install RKE2 (primary generates token)
│  ├─ Secondary nodes join
│  └─ Deploy Rancher on manager
│
├─ Create nprd-apps cluster in Rancher (30 sec)
│  ├─ rancher2_cluster resource creates cluster object
│  ├─ Automatically extracts registration token
│  └─ Extracts CA checksum
│
└─ Apps cluster deployment (15-20 min)
   ├─ Create 3 VMs (404-406)
   ├─ Install RKE2 (primary first)
   ├─ Add hosts entry for rancher.example.com
   ├─ Download and run system-agent installer
   ├─ Register with Rancher Manager
   ├─ System-agent downloads RKE2 components
   └─ Secondary nodes join RKE2 cluster

Total Time: ~40-50 minutes (VMs + RKE2 + Automatic Rancher registration)
```
````

## Troubleshooting

### Issue: "curl: (7) Failed to connect to get.rke2.io"

**Cause**: Node can't reach GitHub to download RKE2  
**Solution**: 
- Verify DNS is working: `nslookup github.com`
- Check upstream connectivity: `ping 1.1.1.1`
- Verify VLAN 14 is properly configured on Proxmox switch

### Issue: "curl: (60) SSL certificate problem"

**Cause**: Node can't verify Rancher's HTTPS certificate  
**Solution**:
- Verify CA checksum is correct (from Rancher UI)
- Check DNS resolution: `nslookup rancher.dataknife.net`
- Verify hosts entry: `cat /etc/hosts | grep rancher`
- Test with `-k` flag (insecure) to verify connectivity, then fix cert

### Issue: Cluster appears but nodes aren't joining

**Cause**: System-agent script didn't run or failed  
**Solution**:
1. SSH to node and check: `systemctl status rancher-system-agent`
2. View logs: `journalctl -u rancher-system-agent -n 50`
3. Verify token is valid (hasn't expired from Rancher UI)
4. Re-run registration script manually with verbose output:
   ```bash
   curl -kfL https://rancher.dataknife.net/system-agent-install.sh | bash -x
   ```

### Issue: "registration_token invalid" or "token has expired"

**Cause**: Registration token is no longer valid  
**Solution**:
1. Get new token from Rancher UI: Cluster Management → Add Cluster → Custom
2. Update `terraform.tfvars`:
   ```hcl
   rancher_registration_token = "new-token-from-ui"
   rancher_ca_checksum        = "new-checksum-from-ui"
   ```
3. Redeploy with `terraform apply`

### Issue: DNS not working (nodes can't resolve rancher.dataknife.net)

**Cause**: DNS servers wrong or not applied  
**Solution**:

1. **Check current DNS**:
   ```bash
   ssh ubuntu@192.168.14.110
   resolvectl status
   ```

2. **Update DNS via netplan** (if wrong):
   ```bash
   # Create/edit netplan file
   sudo cat > /etc/netplan/01-netcfg.yaml << 'EOF'
   network:
     version: 2
     ethernets:
       eth0:
         dhcp4: false
         addresses:
           - 192.168.14.110/24
         gateway4: 192.168.14.1
         nameservers:
           addresses: [192.168.14.1, 192.168.1.1]
   EOF
   
   # Apply and verify
   sudo netplan apply
   resolvectl status
   ```

3. **Update `terraform.tfvars`** to ensure proper values:
   ```hcl
   clusters = {
     nprd-apps = {
       dns_servers = ["192.168.14.1", "192.168.1.1"]
     }
   }
   ```

4. **Redeploy**:
   ```bash
   terraform destroy
   rm -f terraform.tfstate*
   terraform apply
   ```

## Advanced Configuration

### Custom Registration Labels

To add custom labels during registration, modify `terraform/main.tf`:

```hcl
# In nprd_apps_primary module:
provisioner "remote-exec" {
  inline = [
    # ... RKE2 installation ...
    "curl -kfL https://${var.rancher_hostname}/system-agent-install.sh | sudo sh -s - \
      --server https://${var.rancher_hostname} \
      --token ${var.rancher_registration_token} \
      --ca-checksum ${var.rancher_ca_checksum} \
      --label 'cattle.io/os=linux' \
      --label 'workload-type=apps' \
      --label 'environment=nprd' \
      --etcd --controlplane --worker"
  ]
}
```

### Custom Agent Configuration

Place custom agent config at `/var/lib/rancher/agent` before registration:

```bash
ssh ubuntu@192.168.14.110
sudo mkdir -p /var/lib/rancher/agent

# Create custom agent config
sudo cat > /var/lib/rancher/agent/agent.yaml << 'EOF'
kind: AgentConfig
apiVersion: rancherd.cattle.io/v1
namespace: cattle-system
EOF

# Then run registration
curl -kfL https://rancher.dataknife.net/system-agent-install.sh | sudo sh -s - ...
```

## Disable Automatic Registration

If you want to deploy without automatic registration:

```hcl
# In terraform.tfvars
register_downstream_cluster = false
```

Then manually register later using the "Manual Registration" section above.

## Monitoring Registration Progress

**In Rancher UI:**
1. Navigate to Cluster Management
2. Look for cluster status (Registering → Active)
3. Check individual node status (all should show Ready)
4. Expand cluster to see agent logs and RKE2 progress

**From kubectl:**
```bash
# Switch to manager cluster
export KUBECONFIG=~/.kube/rancher-manager.yaml

# List clusters
kubectl get clusters.management.cattle.io -n cattle-system

# Check cluster details
kubectl describe clusters.management.cattle.io nprd-apps -n cattle-system

# View agent logs
kubectl get pods -n cattle-system
kubectl logs -n cattle-system -l app=rancher-agent -f
```

**From apps cluster (after registration):**
```bash
# Check system-agent on each node
ssh ubuntu@192.168.14.110
sudo journalctl -u rancher-system-agent -f

# Verify RKE2 is running
sudo systemctl status rke2-server
```

## Implementation Details

### What Changed in Terraform

**1. New Variables** (`variables.tf`):
- `register_downstream_cluster` (boolean, default true)
- `rancher_registration_token` (sensitive, for authentication)
- `rancher_ca_checksum` (for HTTPS verification)

**2. Updated Module** (`modules/proxmox_vm/main.tf`):
- Added variables for registration parameters
- Enhanced provisioner with conditional registration logic
- Hosts file entry for Rancher hostname
- System-agent installation script execution

**3. Updated Configuration** (`terraform.tfvars`):
- Changed DNS from `["8.8.8.8", "8.8.4.4"]` to `["192.168.14.1", "192.168.1.1"]`
- Added registration token and CA checksum
- Enabled registration by default (`register_downstream_cluster = true`)

**4. Updated Deployment** (`main.tf`):
- Passes registration variables to nprd-apps nodes
- Primary node executes system-agent installation
- Secondary nodes also get registration parameters (for future enrollment)

### What Gets Automated

When `register_downstream_cluster = true`:

1. ✅ **DNS Configuration**: Nodes get proper DNS servers
2. ✅ **Hosts Entry**: Rancher hostname added to `/etc/hosts`
3. ✅ **RKE2 Installation**: Full Kubernetes cluster deployed
4. ✅ **System-Agent**: Downloaded and installed automatically
5. ✅ **Registration**: Cluster registers with Rancher Manager
6. ✅ **Agent Configuration**: System-agent starts and runs
7. ✅ **RKE2 Components**: Agent downloads necessary binaries
8. ✅ **Cluster Join**: Nodes join as master/worker nodes

## Related Documentation

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Complete deployment walkthrough
- [DNS_CONFIGURATION.md](DNS_CONFIGURATION.md) - DNS setup for Rancher
- [MODULES_AND_AUTOMATION.md](MODULES_AND_AUTOMATION.md) - Terraform module architecture
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

## Quick Reference

### Enable downstream registration
```hcl
register_downstream_cluster = true
rancher_registration_token = "token-from-ui"
rancher_ca_checksum = "checksum-from-ui"
```

### Disable downstream registration
```hcl
register_downstream_cluster = false
```

### Update registration credentials
```bash
# Get new token from Rancher UI
# Cluster Management → Add Cluster → Custom
# Copy token and CA checksum

# Update terraform.tfvars
vim terraform/terraform.tfvars

# Redeploy
cd terraform
terraform apply
```

### Check registration status
```bash
# In Rancher UI
# Cluster Management → [Your Cluster] → Machines tab

# Or via kubectl
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get machines -A
```

### Manual registration of existing cluster
```bash
# Retrieve token from Rancher UI
# SSH to apps node
ssh ubuntu@192.168.14.110

# Run registration
curl -kfL "https://rancher.dataknife.net/system-agent-install.sh?token=TOKEN&ca_checksum=CHECKSUM" | sudo sh

# Verify
sudo systemctl status rancher-system-agent
```

---

**Status**: ✅ Ready for Production Use  
**Last Tested**: January 3, 2026  
**Compatibility**: Rancher v2.13.1+, RKE2 v1.34.3+rke2r1, Proxmox VE 8.0+
