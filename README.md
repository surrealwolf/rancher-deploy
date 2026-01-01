# Rancher Cluster on Proxmox

Deploy a complete Rancher management cluster and non-production apps cluster on Proxmox using Terraform.

## Features

- ✅ **Automated VM Provisioning**: Create 6 VMs from template with cloud-init
- ✅ **Unified Network**: All VMs on VLAN 14 (192.168.14.0/24)
- ✅ **High Availability**: 3-node manager and 3-node apps clusters
- ✅ **Reliable Deployment**: Using dataknife/pve provider with retry logic
- ✅ **Full Documentation**: Architecture, setup, troubleshooting guides
- ✅ **Infrastructure as Code**: Complete Terraform configuration

## Architecture

- **Rancher Manager Cluster**: 3 nodes (VM 401-403), runs Rancher control plane
- **NPRD Apps Cluster**: 3 nodes (VM 404-406), non-production workloads
- **Network**: VLAN 14 (192.168.14.0/24) for unified management
- **Resources**: 4 CPU cores + 8GB RAM per node

## Prerequisites

- **Proxmox VE 9.x**: With API access
- **Ubuntu 22.04 LTS VM Template**: VM ID 400 with Cloud-Init
- **Terraform**: v1.0 or later
- **SSH Key**: For VM access

## Quick Start

1. **Configure Terraform Variables**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit with your Proxmox API credentials and settings
   ```

2. **Deploy Clusters**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

3. **Access Clusters**
   ```bash
   # Get IP addresses
   terraform output rancher_manager_ip
   terraform output nprd_apps_cluster_ips
   ```

## Documentation

- **[Getting Started](docs/GETTING_STARTED.md)** - Quick setup guide
- **[Terraform Guide](docs/TERRAFORM_GUIDE.md)** - Detailed deployment instructions
- **[Architecture](docs/ARCHITECTURE.md)** - System design and components
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Template Creation](docs/TEMPLATE_CREATION.md)** - VM template setup
- **[Terraform Improvements](docs/TERRAFORM_IMPROVEMENTS.md)** - Provider migration details

## Project Structure

```
.
├── docs/                    # Documentation
│   ├── GETTING_STARTED.md
│   ├── TERRAFORM_GUIDE.md
│   ├── ARCHITECTURE.md
│   ├── TROUBLESHOOTING.md
│   ├── TEMPLATE_CREATION.md
│   └── TERRAFORM_IMPROVEMENTS.md
├── terraform/               # Terraform configuration
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/proxmox_vm/
├── scripts/                 # Utility scripts
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
ssh -i ~/.ssh/id_rsa ubuntu@192.168.14.100

# Verify network
ping 192.168.14.101
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
    gateway     = "192.168.14.1"
    dns_servers = ["192.168.1.1", "192.168.1.2"]
    domain      = "example.com"
  }
  nprd-apps = {
    gateway     = "192.168.14.1"
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
