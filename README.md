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

## Requirements

### Local System Requirements

Your workstation/CI runner executing Terraform must have:

- **Terraform**: v1.5 or later
- **Git**: For version control and cloning this repository
- **SSH Client**: For VM authentication and access
- **curl**: For API testing and Proxmox verification
- **bash or zsh**: Shell environment (recommended for AI-assistant compatibility)
- **Internet access**: To download cloud images, RKE2, and Rancher
- **Git credentials**: Access to GitHub (public repository, no auth required)

**Optional but helpful:**
- `kubectl`: For post-deployment cluster management (can be retrieved from kubeconfig)
- `helm`: For manual Rancher customization (installed automatically during deployment)
- `jq`: For parsing JSON in scripts and debugging

### Proxmox Cluster Requirements

Your Proxmox VE cluster must have:

- **Proxmox VE**: Version 8.0 or later
- **Available Resources**:
  - **CPU**: 24 vCPU cores minimum (12 for manager cluster, 12 for apps cluster)
  - **RAM**: 48GB minimum (24GB for manager, 24GB for apps)
  - **Storage**: 600GB minimum (120GB per 6 VMs + image cache)
  - **Network**: Access to local network segment for VMs + external for RKE2/Rancher downloads

- **Networking**:
  - VLAN support (default VLAN 14 for unified cluster management)
  - DHCP or static IP capability for cloud-init configuration
  - Access to external DNS (1.1.1.1 or local 192.168.1.1)
  - Internet access for downloading Ubuntu cloud images and RKE2 releases

- **Storage**:
  - At least one datastore with 600GB free space (`local-vm-zfs` or similar)
  - Recommended: SSD or NVMe for better performance
  - Support for qcow2 cloud image format

- **API Access**:
  - Proxmox API token with required permissions (see [API_TOKEN_AND_PERMISSIONS.md](docs/API_TOKEN_AND_PERMISSIONS.md))
  - API endpoint accessible from your workstation (typically `https://<proxmox-ip>:8006`)

### Network Requirements

Connectivity from **local system** to:
- ✅ Proxmox API endpoint (`https://<proxmox-ip>:8006/api2/json`)
- ✅ Proxmox SSH (typically port 22)
- ✅ Internet (for downloads): github.com, get.rke2.io, cloud-images.ubuntu.com, docker.io, quay.io

Connectivity from **Proxmox VMs** to:
- ✅ Internet: github.com, get.rke2.io (for RKE2 installer)
- ✅ docker.io, quay.io (for container images)
- ✅ Local DNS/Gateway for networking (192.168.1.1 or equivalent)

### DNS and Hostname Requirements

For Rancher to function properly:

- **DNS Records** required (A and CNAME):
  ```
  manager.example.com          IN A 192.168.1.100
  manager.example.com          IN A 192.168.1.101
  manager.example.com          IN A 192.168.1.102
  rancher.example.com          IN CNAME manager.example.com
  nprd-apps.example.com        IN A 192.168.1.110
  nprd-apps.example.com        IN A 192.168.1.111
  nprd-apps.example.com        IN A 192.168.1.112
  ```

- **Domain name**: Must resolve to all 3 manager cluster nodes for HA
- **See [DNS_CONFIGURATION.md](docs/DNS_CONFIGURATION.md)** for detailed DNS setup

### Supported Platforms

#### Proxmox Versions
- ✅ Proxmox VE 8.x (tested, recommended)
- ✅ Proxmox VE 9.x (tested, recommended)

#### Operating Systems
- ✅ Ubuntu 24.04 LTS (default, cloud image)
- ⚠️ Other Ubuntu versions supported (change cloud image URL in terraform.tfvars)

#### RKE2 Versions
- ✅ v1.34.3+rke2r1 (tested stable, default)
- ✅ Any specific RKE2 release tag (change `rke2_version` in terraform.tfvars)
- ❌ "latest" tag (not supported - must use specific version)

#### Kubernetes
- ✅ RKE2 v1.32+ (supported)
- ✅ High Availability (3+ manager nodes recommended)
- ❌ Single-node clusters (requires manual tfvars modification)

#### Rancher
- ✅ Rancher v2.7.x (tested, default)
- ✅ Rancher v2.8.x (supported)
- ⚠️ Must have valid TLS certificate or use self-signed (auto-generated)

#### Container Runtimes
- ✅ containerd (RKE2 default, auto-configured)

#### Hypervisors (as cloud image targets)
- ✅ QEMU/KVM (Proxmox default)

### API Token Permissions

Your Proxmox API token requires these minimum permissions:

| Permission | Purpose |
|---|---|
| `Datastore.Allocate` | Create and modify datastores |
| `Datastore.Browse` | Access datastore contents |
| `Nodes.Shutdown` | Reboot nodes |
| `Qemu.Allocate` | Create and modify VMs |
| `Qemu.Clone` | Clone VMs |
| `Qemu.Console` | Access VM console |
| `Qemu.Config.*` | Configure VM settings |
| `Qemu.PowerMgmt` | Start/stop/reboot VMs |

**See [docs/API_TOKEN_AND_PERMISSIONS.md](docs/API_TOKEN_AND_PERMISSIONS.md)** for step-by-step token creation guide and complete permissions reference.

### Unsupported / Out of Scope

- ❌ Single-node Proxmox deployments (requires HA infrastructure)
- ❌ Non-QEMU hypervisors
- ❌ Bare metal deployments (use Proxmox VE or similar)
- ❌ Azure, AWS, GCP clouds (Proxmox-only platform)
- ❌ Kubernetes upgrade automation (manual upgrade required)
- ❌ Multi-cluster federation (can deploy multiple independent clusters)
- ❌ Windows VMs (Ubuntu Linux only)

## Prerequisites Summary

This is a quick summary. See **[Requirements](#requirements)** section above for detailed information:

- **Proxmox VE**: 8.0+ with API token access
- **Terraform**: v1.5 or later
- **SSH Key**: For VM authentication
- **Available Resources**: 24 vCPU cores, 48GB RAM, 600GB storage
- **Shell**: `bash` or `zsh` (recommended; Fish shell not ideal for AI-assistant compatibility)

For complete requirements including local system setup, network access, DNS configuration, and API token permissions, see the **[Requirements](#requirements)** section above.

## Quick Start

### 1. Create Proxmox API Token

If you haven't already created an API token, follow the guide at [docs/API_TOKEN_AND_PERMISSIONS.md](docs/API_TOKEN_AND_PERMISSIONS.md). You'll need:
- **proxmox_api_url**: Your Proxmox endpoint
- **proxmox_api_user**: Usually `root@pam`
- **proxmox_api_token_id**: Token name (e.g., `terraform`)
- **proxmox_api_token_secret**: Token secret (generated by Proxmox)

### 2. Prepare Configuration

```bash
cd /home/lee/git/rancher-deploy/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
proxmox_api_url          = "https://pve.example.com:8006/api2/json"
proxmox_api_user         = "root@pam"
proxmox_api_token_id     = "terraform-token"
proxmox_api_token_secret = "your-secret-token"
proxmox_node             = "pve"
rke2_version             = "v1.34.3+rke2r1"  # IMPORTANT: use actual version, not "latest"
rancher_hostname         = "rancher.example.com"
rancher_password         = "your-secure-password"
```

See [docs/TERRAFORM_VARIABLES.md](docs/TERRAFORM_VARIABLES.md) for all options.

### 3. Deploy Infrastructure + Kubernetes

From the root directory:

```bash
# Deploy with automatic logging (recommended)
./scripts/apply.sh

# Or manually from terraform directory
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

**Note**: The `apply.sh` script automatically:
- Enables debug logging (`TF_LOG=debug`)
- Saves logs to: `terraform/terraform-<timestamp>.log`
- Runs terraform apply with auto-approval in background
- Handles all flags internally - just run `./apply.sh`
- Deploys VMs + RKE2 clusters + Rancher in **one step** ✅

**Single-Step Deployment:**
You can deploy everything in one command:
```bash
./scripts/apply.sh
# Automatically deploys:
# 1. VMs (2-3 min)
# 2. RKE2 clusters (10-15 min)
# 3. Rancher (10-15 min)
# Complete deployment: ~35-40 minutes
```

See [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md#deploy-rancher-automatic-with-single-apply) for single-apply Rancher deployment details.

**⚠️ Critical: RKE2 Version**
- Use specific released version: `v1.34.3+rke2r1`
- Do NOT use `"latest"` - it will fail (not a downloadable release)
- Check available versions: https://github.com/rancher/rke2/tags

**⚠️ Critical: RKE2 Port Configuration (HA Clusters)**
- **Port 9345**: Server registration (secondary nodes join primary)
- **Port 6443**: Kubernetes API (kubectl, only after cluster initialized)
- Configured automatically via cloud-init

### 4. Verify Deployment

```bash
# Check manager Kubernetes cluster
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get nodes
kubectl get pods -n kube-system

# Access Rancher
terraform output rancher_url
# Open in browser, login with:
# Username: admin
# Password: <from rancher_password in tfvars>
```

## Documentation

Core documentation for deployment and troubleshooting:

- **[docs/API_TOKEN_AND_PERMISSIONS.md](docs/API_TOKEN_AND_PERMISSIONS.md)** - Proxmox API token creation and minimum required permissions for end-to-end deployment
- **[docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** - Complete deployment walkthrough, includes kubectl tools setup
- **[docs/RANCHER_API_TOKEN_CREATION.md](docs/RANCHER_API_TOKEN_CREATION.md)** - How API tokens are created automatically, manual creation with curl
- **[docs/RANCHER_DOWNSTREAM_MANAGEMENT.md](docs/RANCHER_DOWNSTREAM_MANAGEMENT.md)** - Automatic downstream cluster registration with Rancher Manager
- **[docs/DNS_CONFIGURATION.md](docs/DNS_CONFIGURATION.md)** - DNS records required for Rancher and Kubernetes API access
- **[docs/CLOUD_IMAGE_SETUP.md](docs/CLOUD_IMAGE_SETUP.md)** - Cloud image provisioning and VM configuration
- **[docs/MODULES_AND_AUTOMATION.md](docs/MODULES_AND_AUTOMATION.md)** - Terraform modules, variables, and automation details
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Project Structure

```
.
├── scripts/                      # Helper scripts
│   ├── apply.sh                  # Deploy with automatic logging
│   ├── destroy.sh                # Destroy infrastructure
│   ├── create-rancher-api-token.sh # Create API token manually
│   └── test-rancher-api-token.sh # Test API connectivity
├── README.md                     # This file
├── CHANGELOG.md                  # Version history
├── CODE_OF_CONDUCT.md            # Community guidelines
├── CONTRIBUTING.md               # Development guidelines
├── docs/                         # Core documentation
│   ├── DEPLOYMENT_GUIDE.md       # Complete deployment walkthrough
│   ├── RANCHER_API_TOKEN_CREATION.md # API token creation
│   ├── RANCHER_DOWNSTREAM_MANAGEMENT.md # Downstream registration
│   ├── DNS_CONFIGURATION.md      # DNS setup
│   ├── CLOUD_IMAGE_SETUP.md      # Cloud image provisioning
│   ├── MODULES_AND_AUTOMATION.md # Terraform modules
│   └── TROUBLESHOOTING.md        # Issue resolution
└── terraform/                    # Terraform configuration
    ├── main.tf                   # Cluster definitions
    ├── provider.tf               # Provider configuration
    ├── variables.tf              # Variables
    ├── outputs.tf                # Outputs
    ├── terraform.tfvars.example  # Config template
    ├── fetch-token.sh            # RKE2 token helper
    └── modules/
        ├── proxmox_vm/           # VM creation module
        ├── rke2_manager_cluster/ # Manager verification
        └── rke2_downstream_cluster/ # Apps verification
```

## Key Features

### Reliable VM Creation

The deployment uses the **bpg/proxmox Terraform provider** (v0.90) with:
- ✅ Exponential backoff retry logic for API calls
- ✅ Proper task completion verification
- ✅ Comprehensive error handling
- ✅ Full Proxmox VE 8.x and 9.x support

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

**Terraform Provider**: bpg/proxmox v0.90.0

**Features:**
- ✅ Reliable task polling with exponential backoff retry
- ✅ Better error messages and diagnostics
- ✅ Full Proxmox VE 8.x and 9.x support
- ✅ Improved cloud-init integration
- ✅ Active community (1.7K+ stars, 130+ contributors)

## Next Steps

1. **Review Architecture**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
2. **Follow Deployment Guide**: [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)
3. **Deploy with Terraform**: [TERRAFORM_GUIDE.md](docs/TERRAFORM_GUIDE.md)
4. **Install Kubernetes**: Set up K3s on deployed nodes
5. **Install Rancher**: Deploy Rancher on manager cluster

## Support & Resources

- **Proxmox Documentation**: https://pve.proxmox.com/wiki/Main_Page
- **Terraform Docs**: https://www.terraform.io/docs/
- **Rancher Docs**: https://rancher.com/docs/

## Contributing

Thank you for your interest in contributing! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup and workflow
- Code standards and testing procedures
- Pull request guidelines
- Issue reporting guidelines
- RKE2 version management guidelines

We're committed to maintaining a welcoming community - see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for our standards.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history, features, and major changes.

## License

This project is licensed under the MIT License.

---

**Built with Claude Haiku 4.5** - This project was developed using Claude Haiku 4.5, an AI assistant optimized for code generation and infrastructure automation.
