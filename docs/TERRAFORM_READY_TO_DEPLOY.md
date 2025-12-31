# ✅ Terraform Ready for Deployment

## Current Status

- ✅ Terraform v1.14.3 installed
- ✅ Terraform initialized successfully
- ✅ All providers downloaded (proxmox, helm, kubernetes)
- ✅ VMs 400-406 created and ready

## Next: Configure and Deploy

### Step 1: Create Manager Terraform Variables

```bash
cd /home/lee/git/rancher-deploy/terraform
```

Create a new file called `terraform.tfvars` with your Proxmox credentials:

```hcl
# Proxmox API Configuration
proxmox_api_url      = "https://your-proxmox.com:8006/api2/json"
proxmox_token_id     = "your-token-id"
proxmox_token_secret = "your-token-secret"
proxmox_tls_insecure = true
proxmox_node         = "your-node-name"

# VM Configuration
vm_template_id = 400
ssh_private_key = "~/.ssh/id_rsa"

# Rancher Configuration
rancher_hostname = "rancher.lab.local"
rancher_password = "ChangeMe123!"

# Network
domain      = "lab.local"
dns_servers = ["8.8.8.8", "8.8.4.4"]
storage     = "local-vm-zfs"
```

### Step 2: Validate Configuration

```bash
# Validate Terraform
cd /home/lee/git/rancher-deploy/terraform
terraform validate

# Preview what will be deployed
terraform plan
```

### Step 3: Deploy Infrastructure

```bash
# Apply the configuration (this will deploy both clusters)
terraform apply

# When prompted, review the changes and type "yes" to confirm
```

### Deployment Notes

- **Deployment time**: 30-45 minutes for both clusters
- **Network**: VMs will be configured with:
  - Manager cluster: 192.168.1.100-102
  - NPRD-Apps cluster: 192.168.2.100-102
- **Access**: Rancher will be available at https://rancher.lab.local

### Monitor Deployment

In another terminal, watch the VMs:

```bash
# Check VM status
watch -n 5 'ssh -i ~/.ssh/id_rsa root@pve2 qm list | grep -E "400|401|402|403|404|405|406"'

# Check RKE2 status on first manager node
watch -n 10 'ssh -i ~/.ssh/id_rsa root@192.168.1.100 systemctl status rke2-server'
```

### After Deployment

Once `terraform apply` completes:

1. **Get Kubeconfig**
   ```bash
   terraform output -raw kubeconfig_manager
   ```

2. **Access Rancher**
   - URL: https://rancher.lab.local
   - Username: admin
   - Password: (from rancher_password in tfvars)

3. **Connect to NPRD-Apps Cluster**
   - Both clusters will be auto-registered
   - Managed from Rancher dashboard

---

## Ready to Deploy?

When you're ready, run:

```bash
cd /home/lee/git/rancher-deploy/terraform
cp terraform.tfvars.example terraform.tfvars  # if needed
# Edit terraform.tfvars with your values
terraform apply
```

