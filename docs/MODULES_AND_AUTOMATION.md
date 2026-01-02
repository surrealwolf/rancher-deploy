# Terraform Rancher Deployment - Complete Setup

## Overview

The rancher-deploy project now provides **end-to-end automation** for deploying Rancher on Proxmox using Terraform. This includes:

1. **VM Provisioning** - bpg/proxmox provider
2. **RKE2 Installation** - Automated Kubernetes bootstrapping
3. **Rancher Deployment** - Helm-based installation

## New Modules

### 1. rke2_cluster Module
**Location:** `terraform/modules/rke2_cluster/main.tf`

Automates RKE2 Kubernetes installation via SSH provisioners:
- Installs RKE2 on server nodes
- Joins additional servers in HA mode
- Retrieves and stores kubeconfig locally
- Handles token management for cluster joining

**Key Features:**
- Zero-downtime cluster formation
- Automatic kubeconfig retrieval
- Support for multiple server nodes
- Optional agent nodes

### 2. rancher_cluster Module
**Location:** `terraform/modules/rancher_cluster/main.tf`

Deploys Rancher via Helm with dependencies:
- Installs cert-manager (for TLS)
- Deploys Rancher Helm chart
- Configures bootstrap password
- Sets up Ingress for HTTPS

**Key Features:**
- Kubernetes and Helm providers configured
- Automatic namespace creation
- TLS with Let's Encrypt ready
- Multi-replica Rancher deployment

## Updated main.tf

The main Terraform file now orchestrates:

```hcl
# 1. Provision VMs
module "rancher_manager" { ... }
module "nprd_apps" { ... }

# 2. Install RKE2
module "rke2_manager" { ... }
module "rke2_apps" { ... }

# 3. Deploy Rancher
module "rancher_deployment" { ... }
```

## Deployment Workflow

```
terraform apply
├── 1. Create VMs (10-15 min)
│   ├── Proxmox VM provisioning
│   ├── Cloud-init networking setup
│   └── SSH connectivity verification
├── 2. Install RKE2 (15-20 min)
│   ├── Install RKE2 on first server
│   ├── Join additional servers
│   ├── Retrieve kubeconfig
│   └── Store locally in ~/.kube/
└── 3. Deploy Rancher (5-10 min)
    ├── Install cert-manager
    ├── Deploy Rancher Helm chart
    ├── Configure bootstrap password
    └── Create Ingress rules

Total Time: 30-45 minutes
```

## Configuration Required

Update `terraform/terraform.tfvars`:

```hcl
# Existing (Proxmox)
proxmox_api_url = "https://pve.example.com:8006/api2/json"
proxmox_api_user = "root@pam"
proxmox_api_token_id = "terraform"
proxmox_api_token_secret = "xxx-xxx-xxx"
proxmox_node = "pve"

# Existing (Clusters)
clusters = {
  manager = {
    node_count = 3
    # ... other settings
  }
  nprd-apps = {
    node_count = 3
    # ... other settings
  }
}

# NEW (Rancher)
rancher_version = "v2.7.7"
rancher_password = "your-secure-bootstrap-password"
rancher_hostname = "rancher.example.com"

# Existing (SSH)
ssh_private_key = "~/.ssh/id_rsa"
```

## Deployment Steps

```bash
# 1. Initialize Terraform
cd /home/lee/git/rancher-deploy/terraform
terraform init

# 2. Preview changes
terraform plan

# 3. Deploy everything
terraform apply

# 4. Monitor progress
# Watch the logs in another terminal:
terraform apply -input=false 2>&1 | tail -f

# 5. Access Rancher
terraform output rancher_url
# Username: admin
# Password: <from rancher_password>
```

## Outputs

After successful deployment:

```bash
terraform output

# Returns:
# cluster_ips = {
#   "manager"   = ["192.168.1.100", "192.168.1.101", "192.168.1.102"]
#   "nprd_apps" = ["192.168.1.110", "192.168.1.111", "192.168.1.112"]
# }
# kubeconfig_paths = {
#   "manager"   = "~/.kube/rancher-manager.yaml"
#   "nprd_apps" = "~/.kube/nprd-apps.yaml"
# }
# rancher_url = "https://rancher.example.com"
```

## Using kubeconfig

```bash
# Manager cluster
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get nodes
kubectl get pods -n cattle-system

# Apps cluster
export KUBECONFIG=~/.kube/nprd-apps.yaml
kubectl get nodes
```

## Customization Options

### Change RKE2 Version
Edit `main.tf`:
```hcl
module "rke2_manager" {
  rke2_version = "v1.27.5"
}
```

### Change Rancher Version
Edit `terraform.tfvars`:
```hcl
rancher_version = "v2.8.0"
```

### Customize Rancher Ingress
Edit `modules/rancher_cluster/main.tf`:
```hcl
set {
  name  = "ingress.class"
  value = "traefik"  # or "nginx", etc
}
```

### Add More Nodes
Edit `terraform.tfvars`:
```hcl
clusters = {
  manager = {
    node_count = 5  # More nodes for HA
  }
}
```

## Troubleshooting

### SSH Connection Fails
```bash
# Verify SSH key
ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.100

# Check if cloud-init is complete
cloud-init status
```

### RKE2 Installation Hangs
```bash
# Check logs on VM
ssh ubuntu@192.168.1.100
sudo journalctl -u rke2-server -f
```

### Kubernetes Nodes Not Ready
```bash
# Check node status
kubectl get nodes -o wide

# Check logs
kubectl describe node <node-name>
```

### Rancher Pod Stuck in Pending
```bash
# Check cert-manager
kubectl get pods -n cert-manager

# Check Rancher logs
kubectl logs -n cattle-system -l app=rancher --tail=100
```

## Next Steps

After Rancher is deployed:

1. **Access Rancher UI**
   ```
   https://rancher.example.com
   Username: admin
   Password: <from tfvars>
   ```

2. **Change admin password** in Rancher UI

3. **Register apps cluster** - Use Rancher UI to add the apps cluster

4. **Configure authentication** - LDAP, OIDC, GitHub, etc.

5. **Deploy applications** - Use Rancher to manage workloads

6. **Set up monitoring** - Prometheus, Grafana, etc.

## Module Dependencies

```
proxmox_vm (VMs)
    ↓
rke2_cluster (RKE2 Installation)
    ↓
rancher_cluster (Rancher Deployment)
```

All dependencies are configured in `main.tf` with `depends_on` blocks to ensure proper ordering.

## Testing the Setup

### Pre-Deployment
```bash
terraform plan -out=tfplan
terraform show tfplan
```

### During Deployment
```bash
# Monitor Terraform output
terraform apply 2>&1 | grep -E "^module\.|^aws_|^kubernetes_|^helm_"
```

### Post-Deployment
```bash
# Verify all nodes
kubectl get nodes

# Verify Rancher
kubectl get helmrelease -n cattle-system
kubectl get pods -n cattle-system

# Verify DNS/Ingress
kubectl get ingress -n cattle-system
curl -k https://rancher.example.com/health
```

## Security Notes

- **API Token**: Stored in tfvars (add to .gitignore!)
- **SSH Key**: Referenced from ~/.ssh/ (ensure 600 permissions)
- **Rancher Password**: Defined in tfvars (change in UI immediately after login)
- **Ingress TLS**: Automatically provisioned with Let's Encrypt

## Performance Tuning

### For larger deployments:
```hcl
# Increase resources in terraform.tfvars
clusters = {
  manager = {
    cpu_cores  = 8      # from 4
    memory_mb  = 16384  # from 8192
    disk_size_gb = 200  # from 50
  }
}
```

### For faster deployments:
```bash
# Use newer RKE2 version
# Increase worker node count
# Pre-warm image (multiple deployments)
```

## Cleanup

To destroy everything:

```bash
# Destroy Rancher and RKE2
terraform destroy

# Confirm all VMs are gone
pvesh get /nodes/pve/qemu
```

## References

- [bpg/proxmox Provider](https://github.com/bpg/terraform-provider-proxmox)
- [RKE2 Documentation](https://docs.rke2.io/)
- [Rancher Documentation](https://rancher.com/docs/)
- [Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm)
