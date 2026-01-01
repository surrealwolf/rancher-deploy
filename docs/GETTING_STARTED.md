# Getting Started with Rancher on Proxmox

This guide walks you through deploying a Rancher management cluster and non-production apps cluster on Proxmox using Terraform.

## Prerequisites

- **Proxmox VE 9.x**: Access to Proxmox cluster with API token
- **Ubuntu 22.04 LTS VM Template**: With Cloud-Init support
- **Terraform**: v1.0 or higher
- **SSH Key**: For VM access (default: `~/.ssh/id_rsa`)
- **kubectl**: For cluster management
- **helm**: For Rancher installation (optional for initial deployment)

## Quick Start

### 1. Create Proxmox API Token

In Proxmox UI:
1. Settings → Users → Select your user
2. API Tokens → Add Token
3. Grant permissions: Datastore, Nodes, VMs
4. Note the token ID and secret

### 2. Create Ubuntu VM Template

```bash
# SSH to Proxmox node and run:
qm create 400 --name ubuntu-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Download Ubuntu 22.04 Cloud-Init image and import
# See docs/TEMPLATE_CREATION.md for detailed instructions
```

### 3. Configure Terraform Variables

```bash
# Copy terraform.tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your values:
# - proxmox_api_url: https://your-proxmox:8006/api2/json
# - proxmox_api_user: terraform@pam
# - proxmox_api_token_id: your-token-id
# - proxmox_api_token_secret: your-token-secret
# - ssh_private_key: /path/to/private/key
```

### 4. Deploy Clusters

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# This creates:
# - 3 Rancher manager nodes (VMs 401-403)
# - 3 NPRD apps nodes (VMs 404-406)
```

### 5. Access Clusters

After deployment, clusters are accessible at their respective IP addresses. Get IPs from Terraform outputs:

```bash
terraform output rancher_manager_ip
terraform output nprd_apps_cluster_ips
```

## Project Structure

```
.
├── docs/                  # Documentation
│   ├── GETTING_STARTED.md # This file
│   ├── TEMPLATE_CREATION.md
│   ├── TERRAFORM_GUIDE.md
│   ├── ARCHITECTURE.md
│   └── TROUBLESHOOTING.md
├── terraform/             # Terraform configuration
│   ├── main.tf
│   ├── variables.tf
│   ├── provider.tf
│   ├── outputs.tf
│   └── modules/
│       └── proxmox_vm/
├── scripts/               # Utility scripts
│   ├── setup.sh
│   └── SETUP_COMPLETE.sh
├── .github/               # GitHub configuration
│   └── copilot-instructions.md
└── README.md              # Project overview
```

## Next Steps

- Review [TERRAFORM_GUIDE.md](TERRAFORM_GUIDE.md) for detailed Terraform information
- Check [TEMPLATE_CREATION.md](TEMPLATE_CREATION.md) for VM template setup
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Support

For issues and questions:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
2. Review Terraform logs: `TF_LOG=debug terraform apply`
3. Check Proxmox task history for VM creation details
