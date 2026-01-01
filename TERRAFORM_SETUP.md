# Rancher Deploy - Terraform Setup

## Overview

This project uses Terraform to deploy Rancher manager and NPRD apps clusters on Proxmox VE using a custom terraform-pve provider.

## Custom Provider

The project uses a custom Terraform provider: **dataknife/pve** (terraform-pve)

Location: `/home/lee/git/terraform-pve`

### Key Features
- Creates QEMU VMs by cloning from templates
- Configures VM resources (CPU, memory, disk, network)
- Properly implements Delete operation to remove VMs from Proxmox
- Supports cloud-init for VM initialization

### Provider Configuration

The provider is configured in each environment's `main.tf`:

```hcl
provider "pve" {
  endpoint         = var.proxmox_api_url
  api_user         = var.proxmox_api_user
  api_token_id     = var.proxmox_token_id
  api_token_secret = var.proxmox_token_secret
  insecure         = var.proxmox_tls_insecure
}
```

## Project Structure

```
rancher-deploy/
├── terraform/
│   └── environments/
│       ├── manager/          # Rancher manager cluster (VMs 401-403)
│       └── nprd-apps/        # NPRD apps cluster (VMs 404-406)
└── ...
```

## Environments

### Manager Environment

Located at: `terraform/environments/manager/`

Creates 3 Rancher manager VMs:
- **rancher-manager-1**: VM ID 401, IP 192.168.14.10
- **rancher-manager-2**: VM ID 402, IP 192.168.14.11
- **rancher-manager-3**: VM ID 403, IP 192.168.14.12

**Deploy:**
```bash
cd terraform/environments/manager
terraform init
terraform plan
terraform apply
```

**Destroy:**
```bash
terraform destroy
```

### NPRD Apps Environment

Located at: `terraform/environments/nprd-apps/`

Creates 3 NPRD apps cluster VMs:
- **nprd-apps-1**: VM ID 404, IP 192.168.14.100
- **nprd-apps-2**: VM ID 405, IP 192.168.14.101
- **nprd-apps-3**: VM ID 406, IP 192.168.14.102

**Deploy:**
```bash
cd terraform/environments/nprd-apps
terraform init
terraform plan
terraform apply
```

**Destroy:**
```bash
terraform destroy
```

## VM ID Allocation

- **Template**: VM 400 (ubuntu-22.04-template)
- **Manager Cluster**: VMs 401-403
- **NPRD Apps Cluster**: VMs 404-406
- **Existing VMs**: 100-115, 120, 102-110 (qbc series, various services)

## Authentication

### API Token Format

The custom provider expects:
- `api_user`: User account (e.g., `root@pam`)
- `api_token_id`: Token name (e.g., `root-mcp`)
- `api_token_secret`: Token secret UUID

The provider constructs the full token as: `{api_user}!{api_token_id}={api_token_secret}`

### Creating a Token in Proxmox

1. Log into Proxmox Web UI
2. Navigate to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Fill in:
   - User: `root@pam` (or your user)
   - Token ID: `root-mcp` (or your choice)
   - Privileges: Select appropriate privileges
5. Copy the token secret (only shown once)

## Configuration

Each environment has a `terraform.tfvars` file with:
- Proxmox API URL and credentials
- VM template ID (400)
- VM ID base (for each cluster)
- Resource specifications (CPU, memory, disk)
- Network configuration (gateway, DNS servers, storage)

## Notes

- The custom provider properly implements the Delete operation, allowing `terraform destroy` to remove VMs from Proxmox
- VMs are created by cloning from the template (VM 400)
- Cloud-init is configured to set up the ubuntu user with specified IP configuration
- Both clusters use the same network subnet (192.168.14.0/24) with different IP ranges

## Troubleshooting

### Provider Not Found

If you get "provider not installed" errors:

```bash
cd /home/lee/git/terraform-pve
make install
```

This rebuilds and installs the custom provider to `~/.terraform.d/plugins/`.

### Module Not Installed

Reinitialize Terraform:

```bash
cd terraform/environments/{manager|nprd-apps}
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### Destroy Doesn't Remove VMs

Ensure you're using the latest version of the custom provider with the Delete function implemented. Rebuild if needed:

```bash
cd /home/lee/git/terraform-pve
make install
```

Then reinitialize in the environment directory.
