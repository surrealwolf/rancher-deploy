# Terraform Deployment Guide

Comprehensive guide to deploying Rancher clusters on Proxmox using Terraform.

## Architecture

The deployment creates two separate Kubernetes clusters on Proxmox:

### Rancher Manager Cluster
- **Purpose**: Runs Rancher management plane
- **Nodes**: 3 VMs (VM 401-403)
- **Network**: VLAN 14 (192.168.14.10x)
- **Resources**: 4 CPU cores, 8GB RAM each
- **Storage**: 20GB root disk

### NPRD Apps Cluster
- **Purpose**: Non-production application cluster
- **Nodes**: 3 VMs (VM 404-406)
- **Network**: VLAN 14 (192.168.14.11x)
- **Resources**: 4 CPU cores, 8GB RAM each
- **Storage**: 20GB root disk

## Configuration

### Provider Configuration

The deployment uses the `dataknife/pve` Terraform provider (v1.0.0), which provides improved reliability and performance over the older `telmate/proxmox` provider.

**Key improvements:**
- Reliable task polling with retry logic
- Better error handling and reporting
- Configurable logging for debugging
- Support for modern Proxmox VE 9.x APIs

### Variables

Edit `terraform/terraform.tfvars`:

```hcl
# Proxmox connection
proxmox_api_url          = "https://proxmox.example.com:8006/api2/json"
proxmox_api_user         = "terraform@pam"
proxmox_api_token_id     = "your-token-id"
proxmox_api_token_secret = "your-token-secret"
proxmox_tls_insecure     = false  # Use true only for testing

# VM Configuration
proxmox_node             = "pve1"
proxmox_storage          = "local-vm-zfs"
vm_template_id           = 400    # Your Ubuntu template VM ID
ssh_private_key          = "~/.ssh/id_rsa"

# Cluster Configuration
clusters = {
  manager = {
    gateway    = "192.168.14.1"
    dns_servers = ["192.168.1.1", "192.168.1.2"]
    domain     = "example.com"
  }
  nprd-apps = {
    gateway    = "192.168.14.1"
    dns_servers = ["192.168.1.1", "192.168.1.2"]
    domain     = "example.com"
  }
}
```

## Deployment Workflow

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

This downloads the required providers and initializes the Terraform working directory.

### Step 2: Plan Deployment

```bash
terraform plan -out=tfplan
```

Review the planned changes:
- VM creation details
- Network configuration
- Resource allocation

### Step 3: Apply Configuration

```bash
terraform apply tfplan
```

The deployment will:
1. Create 6 VMs from the Ubuntu template
2. Configure each VM with cloud-init
3. Set up network configuration (VLAN 14)
4. Wait for VMs to stabilize before returning

**Typical timing:**
- Per VM: 20-30 seconds
- Total deployment: ~2-3 minutes for all 6 VMs

### Step 4: Verify Deployment

```bash
# Get manager cluster IPs
terraform output rancher_manager_ip

# Get apps cluster IPs
terraform output nprd_apps_cluster_ips

# Test SSH access
ssh -i ~/.ssh/id_rsa ubuntu@192.168.14.100
```

## Troubleshooting

### VM Creation Timeout

**Symptom:** Terraform apply takes longer than 3 minutes or times out

**Solutions:**
1. Enable debug logging:
   ```bash
   export PROXMOX_LOG_LEVEL=debug
   terraform apply
   ```

2. Check Proxmox task history for VM creation status

3. Verify VM template ID matches configuration

4. Check disk space on Proxmox storage

### Network Configuration Issues

**Symptom:** VMs created but network not responding

**Check:**
1. VLAN 14 is properly configured on vmbr0
2. Cloud-init configuration applied correctly
3. Check IP configuration: `ssh ubuntu@<ip> "ip addr show"`

### SSH Connection Errors

**Symptom:** "Permission denied (publickey)"

**Solutions:**
1. Verify SSH private key path in terraform.tfvars
2. Check cloud-init completed: `journalctl -u cloud-init`
3. Ensure public key in template's authorized_keys

## Advanced Configuration

### Custom VM Sizes

Edit `terraform/variables.tf` and modify default values:

```hcl
variable "vm_cpu_cores" {
  default = 4  # Change cores
}

variable "vm_memory_mb" {
  default = 8192  # Change memory (MB)
}

variable "vm_disk_size_gb" {
  default = 20  # Change disk size
}
```

### Multiple Proxmox Nodes

Modify `terraform/main.tf` to use different nodes for load balancing:

```hcl
module "rancher_manager" {
  for_each = toset(["pve1", "pve2", "pve3"])
  
  source = "./modules/proxmox_vm"
  
  proxmox_node = each.value
  # ... other config
}
```

## Destruction

To tear down the deployment:

```bash
terraform destroy
```

**Note:** This will delete all created VMs. Data cannot be recovered.

## Related Documentation

- [GETTING_STARTED.md](GETTING_STARTED.md) - Quick start guide
- [TEMPLATE_CREATION.md](TEMPLATE_CREATION.md) - VM template creation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [TERRAFORM_IMPROVEMENTS.md](TERRAFORM_IMPROVEMENTS.md) - Provider improvements
