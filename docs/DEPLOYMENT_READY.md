# 🎯 Rancher Deployment - Ready to Deploy

## What's Complete ✅

### Infrastructure Created
- ✅ Template VM (ID 400): ubuntu-22.04-template
- ✅ Manager Cluster VMs (401-403): Ready for deployment
- ✅ NPRD-Apps Cluster VMs (404-406): Ready for deployment
- ✅ All VMs cloned and configured in Proxmox

### Terraform Prepared  
- ✅ Terraform v1.14.3 installed
- ✅ All providers initialized (proxmox, helm, kubernetes)
- ✅ Module paths fixed
- ✅ Configuration files ready

---

## What's Next

### Step 1: Configure Credentials

Edit the terraform variables file:

```bash
cat > /home/lee/git/rancher-deploy/terraform/terraform.tfvars << 'EOF'
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
EOF
```

### Step 2: Preview Changes

```bash
cd /home/lee/git/rancher-deploy/terraform
terraform plan
```

### Step 3: Deploy

```bash
terraform apply
```

When prompted, type **`yes`** to confirm.

---

## Deployment Timeline

| Phase | Duration | Details |
|-------|----------|---------|
| VM Provisioning | 5-10 min | Configuring 6 VMs from template |
| RKE2 Installation | 10-15 min | Installing Kubernetes on all nodes |
| Rancher Deployment | 10-15 min | Installing Rancher management platform |
| cert-manager Setup | 5 min | TLS certificate management |
| **Total** | **30-45 min** | Full stack deployment |

---

## What Gets Deployed

### Manager Cluster (VMs 401-403)
- **3 Kubernetes control plane nodes**
- IP Range: 192.168.1.100-102
- Runs: Rancher Server, cert-manager, monitoring

### NPRD-Apps Cluster (VMs 404-406)
- **3 Kubernetes worker nodes**
- IP Range: 192.168.2.100-102
- Managed by Rancher manager cluster

---

## After Deployment

### Access Rancher

```bash
# Get Kubeconfig for kubectl access
cd /home/lee/git/rancher-deploy/terraform
terraform output -raw kubeconfig_manager > ~/.kube/rancher-config

# Use kubeconfig
export KUBECONFIG=~/.kube/rancher-config
kubectl get nodes
```

**URL**: https://rancher.lab.local  
**Username**: admin  
**Password**: (from rancher_password in tfvars)

### Verify Kubernetes

```bash
# Check nodes
kubectl get nodes

# Check Rancher pods
kubectl get pods -n cattle-system

# Check Helm releases
helm list -A
```

---

## Documentation Reference

- [PROXMOX_MCP_TEMPLATE_REVIEW.md](/home/lee/git/PROXMOX_MCP_TEMPLATE_REVIEW.md) - Architecture & planning
- [TEMPLATE_CREATION_COMPLETE.md](/home/lee/git/TEMPLATE_CREATION_COMPLETE.md) - Template creation summary
- [TERRAFORM_DEPLOYMENT_GUIDE.md](/home/lee/git/TERRAFORM_DEPLOYMENT_GUIDE.md) - Detailed deployment guide
- [TERRAFORM_READY_TO_DEPLOY.md](/home/lee/git/TERRAFORM_READY_TO_DEPLOY.md) - Quick start

---

## Quick Commands

```bash
# Navigate to terraform directory
cd /home/lee/git/rancher-deploy/terraform

# Initialize (already done)
terraform init

# Validate configuration
terraform validate

# Preview deployment
terraform plan

# Deploy infrastructure
terraform apply

# Get outputs
terraform output

# Monitor logs
tail -f terraform-apply.log

# Cleanup (if needed)
terraform destroy
```

---

## Success Indicators ✅

After `terraform apply` completes successfully:

- [ ] All 6 VMs are running
- [ ] All Kubernetes nodes show as "Ready"
- [ ] Rancher dashboard is accessible
- [ ] NPRD-Apps cluster is registered in Rancher
- [ ] DNS resolution works for rancher.lab.local

---

## Status: **READY FOR DEPLOYMENT** 🚀

All prerequisites are complete. The infrastructure is ready to be deployed with Terraform.

