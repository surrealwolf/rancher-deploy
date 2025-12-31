# Terraform Deployment Guide - Rancher on Proxmox

## Prerequisites

Before deploying, ensure you have:

- ✅ Terraform >= 1.0 installed
- ✅ Proxmox VE API token with permissions
- ✅ SSH key configured for VM access
- ✅ VMs 401-406 created and ready (completed)
- ✅ Proxmox network bridges configured (vmbr0)

### Verify Terraform Installation

```bash
terraform version
# Output should show Terraform v1.x or higher
```

---

## Step 1: Initialize Manager Cluster Environment

```bash
# Navigate to manager environment
cd /home/lee/git/rancher-deploy/terraform/environments/manager

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration (see below for values)
vim terraform.tfvars  # or use your preferred editor
```

### Configure terraform.tfvars for Manager

Edit `/home/lee/git/rancher-deploy/terraform/environments/manager/terraform.tfvars`:

```hcl
# Proxmox Configuration
proxmox_api_url      = "https://your-proxmox.com:8006/api2/json"
proxmox_token_id     = "your-token-id"
proxmox_token_secret = "your-token-secret"
proxmox_tls_insecure = true
proxmox_node         = "your-node-name"

# VM Template (ID 400 - created by Proxmox MCP)
vm_template_id = 400

# SSH Configuration
ssh_private_key = "~/.ssh/id_rsa"

# Rancher Configuration
rancher_hostname = "rancher.lab.local"
rancher_password = "YourSecurePassword123!"
rancher_version  = "v2.7.7"

# Network Configuration
domain      = "lab.local"
dns_servers = ["8.8.8.8", "8.8.4.4"]
storage     = "local-vm-zfs"

# Cluster Configuration
clusters = {
  manager = {
    name           = "rancher-manager"
    node_count     = 3
    cpu_cores      = 4
    memory_mb      = 8192
    disk_size_gb   = 100
    domain         = "lab.local"
    ip_subnet      = "192.168.1.0/24"
    gateway        = "192.168.1.1"
    dns_servers    = ["8.8.8.8", "8.8.4.4"]
    storage        = "local-vm-zfs"
  }
}
```

### Required Values to Customize

| Variable | Value | Source |
|----------|-------|--------|
| `proxmox_api_url` | Your Proxmox API endpoint | Proxmox Web UI URL |
| `proxmox_token_id` | Your API token ID | From `mcp.json` |
| `proxmox_token_secret` | Your API token secret | From `mcp.json` |
| `ssh_private_key` | Path to SSH key | Your local key |
| `rancher_password` | Admin password | Choose secure password |
| `proxmox_node` | `pve2` | Where VMs are created |

---

## Step 2: Terraform Plan for Manager

Validate and preview changes:

```bash
# Initialize Terraform (downloads providers)
terraform init

# Validate configuration
terraform validate

# Preview what will be created
terraform plan -out=manager.plan
```

### What to Expect

The plan should show:
- ✅ 3 manager cluster VMs (401-403)
- ✅ Network configuration for 192.168.1.0/24
- ✅ RKE2 installation via provisioners
- ✅ Rancher Helm deployment
- ✅ cert-manager installation

---

## Step 3: Apply Manager Cluster

```bash
# Apply the plan
terraform apply manager.plan

# Or apply directly (will prompt for confirmation)
terraform apply
```

### Deployment Timeline

- **VM Configuration**: 5-10 minutes
- **RKE2 Installation**: 10-15 minutes
- **Rancher Deployment**: 10-15 minutes
- **cert-manager Setup**: 5 minutes
- **Total**: ~30-45 minutes

Monitor progress:

```bash
# Watch Terraform output
terraform apply 2>&1 | tee deploy.log

# Check VM status in Proxmox
watch -n 5 'ssh root@pve2 qm list | grep manager'
```

---

## Step 4: Initialize NPRD-Apps Cluster Environment

Once manager cluster is ready:

```bash
# Navigate to NPRD-Apps environment
cd /home/lee/git/rancher-deploy/terraform/environments/nprd-apps

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
vim terraform.tfvars
```

### Configure terraform.tfvars for NPRD-Apps

Edit `/home/lee/git/rancher-deploy/terraform/environments/nprd-apps/terraform.tfvars`:

```hcl
# Proxmox Configuration (same as manager)
proxmox_api_url      = "https://your-proxmox.com:8006/api2/json"
proxmox_token_id     = "your-token-id"
proxmox_token_secret = "your-token-secret"
proxmox_tls_insecure = true
proxmox_node         = "your-node-name"

# VM Template
vm_template_id = 400

# SSH Configuration
ssh_private_key = "~/.ssh/id_rsa"

# Network Configuration
domain      = "lab.local"
dns_servers = ["8.8.8.8", "8.8.4.4"]
storage     = "local-vm-zfs"

# Cluster Configuration for NPRD-Apps
clusters = {
  "nprd-apps" = {
    name           = "nprd-apps"
    node_count     = 3
    cpu_cores      = 8
    memory_mb      = 16384
    disk_size_gb   = 150
    domain         = "lab.local"
    ip_subnet      = "192.168.2.0/24"
    gateway        = "192.168.1.1"
    dns_servers    = ["8.8.8.8", "8.8.4.4"]
    storage        = "local-vm-zfs"
  }
}
```

---

## Step 5: Terraform Plan for NPRD-Apps

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan -out=nprd.plan
```

---

## Step 6: Apply NPRD-Apps Cluster

```bash
# Apply the plan
terraform apply nprd.plan

# Or apply directly
terraform apply
```

---

## Step 7: Verify Deployment

After both clusters are deployed:

```bash
# Check manager cluster outputs
cd /home/lee/git/rancher-deploy/terraform/environments/manager
terraform output cluster_ips
terraform output kubeconfig_path

# Check NPRD-Apps outputs
cd ../nprd-apps
terraform output cluster_ips
terraform output kubeconfig_path
```

### Access Rancher Dashboard

1. Get Rancher admin password from Terraform output or kubeconfig
2. Access Rancher at: `https://rancher.lab.local`
3. Login with:
   - Username: `admin`
   - Password: (from terraform.tfvars)

---

## Troubleshooting

### Terraform Init Fails

```bash
# Ensure Proxmox provider is compatible
terraform init -upgrade

# Check terraform version
terraform version

# Verify telmate/proxmox provider is available
terraform providers
```

### Proxmox API Authentication Error

```bash
# Verify token values in mcp.json
cat ~/.config/Code/User/mcp.json | grep -A 5 proxmox-ve-mcp

# Test API access with curl
curl -k -X GET \
  -H "Authorization: PVEAPIToken=your-token-id=your-token-secret" \
  https://your-proxmox.com:8006/api2/json/nodes
```

### VM Provisioning Fails

```bash
# Check VM status in Proxmox
qm list | grep -E "401|402|403|404|405|406"

# Check VM logs
qm monitor 401

# Verify SSH access
ssh -i ~/.ssh/id_rsa root@192.168.1.100
```

### RKE2 Installation Timeout

```bash
# Check RKE2 service status
ssh root@192.168.1.100 systemctl status rke2-server

# View RKE2 logs
ssh root@192.168.1.100 journalctl -u rke2-server -f

# Check installation progress
ssh root@192.168.1.100 kubectl get nodes
```

---

## Post-Deployment Steps

1. **Verify Kubernetes Clusters**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Access Rancher Web UI**
   - Navigate to `https://rancher.lab.local`
   - Complete initial setup
   - Register NPRD-Apps cluster with manager

3. **Configure DNS**
   - Add DNS entry for rancher.lab.local pointing to manager cluster IP
   - Update `/etc/hosts` if no DNS server:
     ```
     192.168.1.100 rancher.lab.local
     ```

4. **Set Up Kubeconfig**
   ```bash
   mkdir -p ~/.kube
   terraform output -raw kubeconfig_path
   # Copy kubeconfig to ~/.kube/config
   ```

---

## Rollback / Destroy

If you need to remove the deployment:

```bash
# Destroy NPRD-Apps cluster
cd /home/lee/git/rancher-deploy/terraform/environments/nprd-apps
terraform destroy

# Destroy manager cluster
cd ../manager
terraform destroy

# Note: This will NOT delete the template VM (ID 400)
# Or the base VMs if you preserved them
```

---

## Success Criteria

✅ Deployment is successful when:

- All 6 VMs are running and configured with correct hostnames
- Kubernetes nodes are in "Ready" state
- Rancher dashboard is accessible
- Both clusters are registered in Rancher management
- Network connectivity between clusters is established
- DNS resolution working for all hostnames

