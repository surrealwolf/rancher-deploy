# Rancher Deploy - Terraform Setup

## Overview

This project uses Terraform to deploy Rancher manager and NPRD apps clusters on Proxmox VE using the **bpg/proxmox** Terraform provider v0.90 with Ubuntu 24.04 LTS cloud images.

## Provider

The project uses **bpg/proxmox** v0.90 - a production-ready Terraform provider for Proxmox VE.

GitHub: https://github.com/bpg/terraform-provider-proxmox (1.7K+ stars, 130+ contributors)

### Key Features
- Native support for Proxmox VE API v2
- Cloud image provisioning with cloud-init
- Full lifecycle management (create, update, delete)
- API token authentication (more secure than password)

### Provider Configuration

The provider is configured in `terraform/provider.tf`:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = "${var.proxmox_api_user}!${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure = var.proxmox_tls_insecure
}
```

## Project Structure

```
rancher-deploy/
├── terraform/
│   ├── main.tf              # Cluster module instantiation
│   ├── provider.tf          # Proxmox provider configuration
│   ├── variables.tf         # Variable definitions
│   ├── terraform.tfvars     # Environment-specific values (not in git)
│   ├── terraform.tfvars.example  # Template for tfvars
│   └── modules/
│       └── proxmox_vm/      # Reusable VM module
├── docs/                    # Documentation
├── DEPLOYMENT_SUMMARY.md    # Deployment record
└── ...
```

## Clusters

IP addresses are sourced from `terraform.tfvars` using the cluster configuration, allowing easy customization without modifying Terraform code.

### Manager Cluster

Creates 3 Rancher manager VMs (IDs 401-403). IPs are calculated from tfvars:
```hcl
clusters.manager.ip_subnet = "192.168.1"      # Base subnet (example)
clusters.manager.ip_start_octet = 100           # Starting octet
```

Results in:
- **rancher-manager-1**: VM ID 401, IP 192.168.1.100
- **rancher-manager-2**: VM ID 402, IP 192.168.1.101
- **rancher-manager-3**: VM ID 403, IP 192.168.1.102

### NPRD Apps Cluster

Creates 3 app cluster VMs (IDs 404-406). IPs are calculated from tfvars:
```hcl
clusters.nprd-apps.ip_subnet = "192.168.1"    # Base subnet (example)
clusters.nprd-apps.ip_start_octet = 110        # Starting octet
```

Results in:
- **nprd-apps-1**: VM ID 404, IP 192.168.1.110
- **nprd-apps-2**: VM ID 405, IP 192.168.1.111
- **nprd-apps-3**: VM ID 406, IP 192.168.1.112

## Deployment

**Deploy all clusters:**
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Customize IPs before deployment:**

Edit `terraform.tfvars` and modify the cluster configuration:

```hcl
clusters = {
  manager = {
    ip_subnet      = "192.168.1"   # Change to your subnet
    ip_start_octet = 100           # Change to your starting IP
    # ... other settings
  }
  nprd-apps = {
    ip_subnet      = "192.168.1"
    ip_start_octet = 110
    # ... other settings
  }
}
```

**Destroy all clusters:**
```bash
cd terraform
terraform destroy
```

## VM ID Allocation

- **Manager Cluster**: VMs 401-403
- **NPRD Apps Cluster**: VMs 404-406

VM IDs are hardcoded in `terraform/main.tf` via the `for_each` loop (401+i for manager, 404+i for apps). Modify the base IDs if needed for your environment.

## Authentication

### API Token Setup

The bpg/proxmox provider requires an API token for authentication:

```hcl
proxmox_api_url = "https://pve.example.com:8006/api2/json"
proxmox_api_user = "root@pam"                              # User account
proxmox_api_token_id = "terraform"                         # Token name
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx..."  # Token secret
```

### Creating a Token in Proxmox

1. SSH into Proxmox node: `ssh root@pve.example.com`
2. Create API token:
   ```bash
   pveum user token add root@pam terraform --privsep=0
   ```
3. Copy the token secret (only shown once)
4. Add to `terraform.tfvars`:
   ```hcl
   proxmox_api_token_secret = "<token-secret-uuid>"
   ```

### Environment Variable Alternative

For security, use environment variables instead of tfvars:

```bash
export PROXMOX_VE_API_URL="https://pve.example.com:8006/api2/json"
export PROXMOX_VE_USERNAME="root@pam"
export PROXMOX_VE_API_TOKEN="terraform@pve!terraform=<secret>"
export PROXMOX_VE_INSECURE=true
```

Then the provider will read these automatically.

## Configuration

All configuration comes from `terraform.tfvars`:

**Proxmox Access:**
- `proxmox_api_url`: Proxmox API endpoint
- `proxmox_api_user`: User account (typically `root@pam`)
- `proxmox_api_token_id`: Token name
- `proxmox_api_token_secret`: Token secret
- `proxmox_node`: Target Proxmox node

**Cloud Images:**
- `ubuntu_cloud_image_url`: Ubuntu cloud image URL (default: 24.04 Noble)

**Cluster Configuration (per cluster):**
- `name`: Cluster name
- `node_count`: Number of VMs
- `cpu_cores`: CPU per VM
- `memory_mb`: Memory per VM
- `disk_size_gb`: Disk size per VM
- `domain`: DNS domain
- `ip_subnet`: Network subnet (e.g., "192.168.1")
- `ip_start_octet`: Starting IP octet (e.g., 100 → 192.168.1.100)
- `gateway`: Network gateway IP
- `dns_servers`: List of DNS servers
- `storage`: Proxmox storage datastore ID

**Rancher Configuration:**
- `rancher_version`: Rancher version (default: v2.7.7)
- `rancher_password`: Initial admin password
- `rancher_hostname`: Rancher manager hostname

**SSH:**
- `ssh_private_key`: Path to SSH key for VM access

## Notes

- VMs are created from Ubuntu cloud images downloaded to the `images-import` storage
- Cloud-init is configured to set up networking, DNS, and hostnames
- Both clusters can use the same subnet with different IP ranges (controlled by `ip_start_octet`)
- Storage must support `images-import` content type for cloud image downloads
- All VM IPs are dynamically calculated: `{ip_subnet}.{ip_start_octet + index}`

## Troubleshooting

### Terraform Validate Fails

```bash
cd terraform
terraform validate
```

If errors occur, check:
- All variables in `terraform.tfvars` match the definitions in `variables.tf`
- Required variables (`proxmox_api_url`, `clusters`, etc.) are defined

### Authentication Issues

**Error:** "authentication failed"

Check:
1. API token exists in Proxmox: `pveum token list`
2. Token secret is correct in `terraform.tfvars`
3. Proxmox API URL is accessible: `curl -k https://pve.example.com:8006/api2/json/version`
4. Token has proper permissions for VM operations

### Cloud Image Download Fails

**Error:** "storage 'images-import' is not configured for content-type 'import'"

Fix: Verify storage exists and supports 'import' content type:

```bash
pvesh get /storage/images-import -noborder=1
```

Output should include `content: import,iso,vztmpl`

### Wrong IPs Assigned

Verify cluster configuration in `terraform.tfvars`:

```hcl
clusters = {
  manager = {
    ip_subnet = "192.168.1"
    ip_start_octet = 100  # Results in 192.168.1.100-102
  }
  # ...
}
```

Then re-plan before applying:

```bash
terraform plan -out=tfplan
terraform show tfplan
```
