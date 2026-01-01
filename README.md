# Rancher Cluster on Proxmox

Deploy a complete Rancher management cluster and non-production apps cluster on Proxmox using Terraform with Ubuntu 24.04 cloud images, RKE2 Kubernetes, and automated Rancher installation.

## Features

- ✅ **Full Automation**: From VMs to Rancher in a single `terraform apply`
- ✅ **Cloud Image Provisioning**: Ubuntu 24.04 LTS cloud images with automatic downloads
- ✅ **Modern Provider**: bpg/proxmox v0.90 (1.7K+ GitHub stars, 130+ contributors)
- ✅ **RKE2 Kubernetes**: Automated RKE2 installation and cluster bootstrapping
- ✅ **Rancher Deployment**: Helm-based Rancher installation with cert-manager
- ✅ **High Availability**: 3-node manager + 3-node apps clusters with HA Rancher
- ✅ **Cloud-Init Integration**: Automated networking, DNS, hostnames
- ✅ **Comprehensive Docs**: Setup guides, variable management, troubleshooting
- ✅ **Secure Configuration**: API token auth, gitignore patterns, tfvars templates

## What's Deployed

- **Rancher Manager**: 3 VMs (401-403) with RKE2 + Rancher control plane
- **Apps Cluster**: 3 VMs (404-406) with RKE2 for non-production workloads
- **Storage**: Dedicated volumes for cloud images + VM storage (local-vm-zfs)
- **Network**: Static IPs, DNS configured via cloud-init
- **Kubernetes**: RKE2 clusters automatically bootstrapped and configured
- **Rancher**: Helm-deployed with cert-manager, Ingress, and bootstrap password

## Prerequisites

- **Proxmox VE 8.0+**: With API token access
- **Terraform**: v1.5 or later
- **SSH Key**: For authentication (optional, password auth supported)
- **Available Resources**: 24 vCPU cores, 48GB RAM, 600GB disk space

## Quick Start

### 1. Prepare Configuration

```bash
cd /home/lee/git/rancher-deploy/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
proxmox_api_url = "https://pve.example.com:8006/api2/json"
proxmox_api_user = "root@pam"
proxmox_api_token_id = "terraform-token"
proxmox_api_token_secret = "your-secret-token"
proxmox_node = "pve"
rancher_hostname = "rancher.example.com"
rancher_password = "your-secure-password"
```

See [docs/TERRAFORM_VARIABLES.md](docs/TERRAFORM_VARIABLES.md) for all options.

### 2. Deploy Infrastructure + Kubernetes + Rancher

```bash
# Verify configuration
terraform init
terraform plan

# Deploy (takes 30-45 minutes including RKE2 installation and Rancher setup)
terraform apply
```

### 3. Verify Deployment

```bash
# Check manager Kubernetes cluster
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get nodes
kubectl get pods -n cattle-system

# Access Rancher
terraform output rancher_url
# Open in browser, login with:
# Username: admin
# Password: <from rancher_password in tfvars>
```

## Documentation

- **[TERRAFORM_SETUP.md](TERRAFORM_SETUP.md)** - Complete Terraform configuration guide
- **[docs/RANCHER_DEPLOYMENT.md](docs/RANCHER_DEPLOYMENT.md)** - Rancher deployment automation
- **[docs/CLOUD_IMAGE_SETUP.md](docs/CLOUD_IMAGE_SETUP.md)** - Cloud image provisioning details
- **[docs/TERRAFORM_VARIABLES.md](docs/TERRAFORM_VARIABLES.md)** - Variable reference
- **[docs/TFVARS_SETUP.md](docs/TFVARS_SETUP.md)** - Setup instructions
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Project Structure

```
.
├── docs/                         # Documentation
│   ├── CLOUD_IMAGE_SETUP.md     # Cloud image provisioning
│   ├── TERRAFORM_VARIABLES.md   # Variable reference
│   ├── TFVARS_SETUP.md          # Setup instructions
│   └── TROUBLESHOOTING.md       # Troubleshooting guide
├── terraform/                    # Terraform configuration
│   ├── main.tf                  # Cluster module instantiation
│   ├── provider.tf              # bpg/proxmox provider config
│   ├── variables.tf             # Variable definitions
│   ├── outputs.tf               # Output values
│   ├── terraform.tfvars         # Environment config (not in git)
│   ├── terraform.tfvars.example # Config template
│   ├── modules/
│   │   └── proxmox_vm/          # Reusable VM module
│   └── environments/            # Legacy environment configs
├── TERRAFORM_SETUP.md           # Terraform guide
├── DEPLOYMENT_SUMMARY.md        # Deployment record
├── README.md                    # This file
├── Makefile                     # Build automation
└── .gitignore                   # Git ignore rules
│   └── setup.sh
├── .github/                 # GitHub configuration
│   └── copilot-instructions.md
└── README.md                # This file
```

## Key Features

### Reliable VM Creation

The deployment uses the **dataknife/pve Terraform provider** (v1.0.0) with:
- ✅ Exponential backoff retry logic for API calls
- ✅ Proper task completion verification
- ✅ Comprehensive error handling
- ✅ Configurable debug logging (PROXMOX_LOG_LEVEL)

### Automated Configuration

Each VM is automatically configured with:
- Cloud-init for OS customization
- Network settings (VLAN 14, static IP, DNS)
- SSH key-based authentication
- Hostname and domain configuration

### Cluster Orchestration

- Manager cluster created first
- Apps cluster waits for manager completion
- Explicit dependencies ensure proper sequencing
- Total deployment time: ~2-3 minutes for all 6 VMs

## Usage

### Deployment

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan changes
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan
```

### Outputs

After successful deployment:

```bash
# Get manager cluster IPs
terraform output rancher_manager_ip

# Get apps cluster IPs
terraform output nprd_apps_cluster_ips
```

### Testing Access

```bash
# SSH to a node
ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.100

# Verify network
ping 192.168.1.101
```

### Cleanup

```bash
terraform destroy
```

## Configuration

### Edit Variables

File: `terraform/terraform.tfvars`

```hcl
# Proxmox API credentials
proxmox_api_url          = "https://proxmox.example.com:8006/api2/json"
proxmox_api_user         = "terraform@pam"
proxmox_api_token_id     = "your-token-id"
proxmox_api_token_secret = "your-token-secret"

# Proxmox settings
proxmox_node   = "pve1"
proxmox_storage = "local-vm-zfs"

# VM configuration
vm_template_id = 400
ssh_private_key = "~/.ssh/id_rsa"

# Cluster settings
clusters = {
  manager = {
    gateway     = "192.168.1.1"
    dns_servers = ["192.168.1.1", "192.168.1.2"]
    domain      = "example.com"
  }
  nprd-apps = {
    gateway     = "192.168.1.1"
    dns_servers = ["192.168.1.1", "192.168.1.2"]
    domain      = "example.com"
  }
}
```

## Troubleshooting

### Common Issues

- **VM creation timeout**: Check Proxmox task history, enable debug logging
- **Network not responding**: Verify VLAN 14 configuration on vmbr0
- **SSH connection refused**: Ensure cloud-init completed, check authorized_keys
- **Authentication failed**: Verify API token credentials and permissions

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions.

### Debug Logging

```bash
# Enable debug output for Terraform
export TF_LOG=debug
terraform apply

# Enable debug output for Proxmox provider
export PROXMOX_LOG_LEVEL=debug
terraform apply
```

## Performance

Deployment timing (typical):
- Single VM creation: 20-30 seconds
- 3-node cluster: 1-1.5 minutes
- All 6 VMs (sequential): 2-3 minutes
- All 6 VMs (parallelized): 1-2 minutes

## Provider Information

**Terraform Provider**: dataknife/pve v1.0.0

**Improvements over older providers:**
- ✅ Reliable task polling with proper retry logic
- ✅ Better error messages and diagnostics
- ✅ Full Proxmox VE 9.x support
- ✅ Improved cloud-init integration
- ✅ Configurable logging for debugging

**Previous Provider**: telmate/proxmox (deprecated)

## Next Steps

1. **Review Architecture**: [ARCHITECTURE.md](docs/ARCHITECTURE.md)
2. **Follow Setup Guide**: [GETTING_STARTED.md](docs/GETTING_STARTED.md)
3. **Deploy with Terraform**: [TERRAFORM_GUIDE.md](docs/TERRAFORM_GUIDE.md)
4. **Install Kubernetes**: Set up K3s on deployed nodes
5. **Install Rancher**: Deploy Rancher on manager cluster

## Support & Resources

- **Proxmox Documentation**: https://pve.proxmox.com/wiki/Main_Page
- **Terraform Docs**: https://www.terraform.io/docs/
- **Rancher Docs**: https://rancher.com/docs/

## License

This project is licensed under the MIT License.

## Contributing

Contributions are welcome! Please ensure:
- Documentation is updated
- Terraform code is properly formatted: `terraform fmt -recursive`
- Changes are tested before submission
