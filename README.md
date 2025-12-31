# Rancher Cluster on Proxmox - Terraform

This Terraform configuration provisions a Rancher cluster on Proxmox with 2 managed clusters:

- **rancher-manager**: Rancher management cluster (3 nodes)
- **nprd-apps**: Non-production apps cluster (3 nodes)

## Prerequisites

1. **Proxmox**: Access to a Proxmox cluster with API token
2. **VM Template**: Ubuntu 22.04 LTS template with Cloud-Init support
3. **Terraform**: v1.0 or higher
4. **SSH Key**: SSH key for VM access
5. **kubectl**: For cluster management
6. **helm**: For Rancher installation

## Setup

### 1. Create Proxmox API Token

```bash
# In Proxmox UI, create a token for Terraform
# Settings -> Users -> Select user -> API Tokens -> Add Token
# Give it necessary permissions (Datastore, Nodes, VMs)
```

### 2. Create Ubuntu VM Template

```bash
# On Proxmox node:
qm create 100 --name ubuntu-22.04 --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
# Download and import Ubuntu 22.04 Cloud-Init image
# Add serial console, Cloud-Init drive, etc.
```

### 3. Configure Variables

Copy the example terraform.tfvars files:

```bash
cd terraform/environments/manager
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

cd ../nprd-apps
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 4. Initialize and Deploy

#### Deploy Manager Cluster

```bash
cd terraform/environments/manager
terraform init
terraform plan
terraform apply
```

#### Deploy NPRD-Apps Cluster

```bash
cd terraform/environments/nprd-apps
terraform init
terraform plan
terraform apply
```

## Cluster Architecture

### Rancher Manager Cluster
- **Nodes**: 3 x 4 CPU, 8GB RAM, 100GB disk
- **Network**: 192.168.1.0/24
- **Components**:
  - cert-manager
  - Rancher Server
  - Monitoring stack

### NPRD-Apps Cluster
- **Nodes**: 3 x 8 CPU, 16GB RAM, 150GB disk
- **Network**: 192.168.2.0/24
- **Registration**: Automatically registered to Rancher manager

## Post-Deployment

### 1. Install Kubernetes

After VMs are created, install Kubernetes on each node:

```bash
# SSH into each node
ssh ubuntu@192.168.1.100
ssh ubuntu@192.168.1.101
ssh ubuntu@192.168.1.102

# Run Kubernetes setup script
curl -s https://raw.githubusercontent.com/rancher/rke2/master/install.sh | INSTALL_RKE2_VERSION="v1.27.0" sh -
systemctl start rke2-server
```

### 2. Configure Kubeconfig

```bash
# Copy kubeconfig from manager node
scp ubuntu@192.168.1.100:/etc/rancher/rke2/rke2.yaml ~/.kube/rancher-manager-config
# Update server IP in kubeconfig

# For NPRD-Apps cluster
scp ubuntu@192.168.2.100:/etc/rancher/rke2/rke2.yaml ~/.kube/nprd-apps-config
```

### 3. Access Rancher

- URL: https://rancher.lab.local
- Username: admin
- Password: (from terraform.tfvars)

## Networking

- **Manager Network**: 192.168.1.0/24
- **NPRD-Apps Network**: 192.168.2.0/24
- **Gateway**: 192.168.1.1
- **DNS**: 8.8.8.8, 8.8.4.4

## Cleanup

To destroy the infrastructure:

```bash
# Remove manager cluster
cd terraform/environments/manager
terraform destroy

# Remove NPRD-Apps cluster
cd terraform/environments/nprd-apps
terraform destroy
```

## Variables Reference

### Manager Environment (`environments/manager/terraform.tfvars`)

```hcl
proxmox_api_url      = "https://proxmox.lab.local:8006/api2/json"
proxmox_token_id     = "terraform@pam!terraform"
proxmox_token_secret = "your-token"
proxmox_tls_insecure = true
proxmox_node         = "pve-01"
vm_template_id       = 100
ssh_private_key      = "~/.ssh/id_rsa"
rancher_hostname     = "rancher.lab.local"
rancher_password     = "SecurePassword123!"
```

### NPRD-Apps Environment (`environments/nprd-apps/terraform.tfvars`)

```hcl
proxmox_api_url      = "https://proxmox.lab.local:8006/api2/json"
proxmox_token_id     = "terraform@pam!terraform"
proxmox_token_secret = "your-token"
proxmox_tls_insecure = true
proxmox_node         = "pve-01"
vm_template_id       = 100
ssh_private_key      = "~/.ssh/id_rsa"
node_count           = 3
cpu_cores            = 8
memory_mb            = 16384
disk_size_gb         = 150
```

## Troubleshooting

### VMs not getting IP addresses
- Ensure Cloud-Init is properly configured in the template
- Check `qemu-guest-agent` is running on VMs

### Rancher UI not accessible
- Wait 5-10 minutes for Rancher to fully initialize
- Check cert-manager status: `kubectl get pods -n cert-manager`
- Check Rancher status: `kubectl get pods -n cattle-system`

### SSH connection issues
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
- Ensure security groups allow SSH on port 22
- Check Proxmox firewall rules

## Module Structure

```
terraform/
├── main.tf                 # Main cluster infrastructure
├── provider.tf            # Terraform providers
├── variables.tf           # Variable definitions
├── outputs.tf             # Output definitions
├── modules/
│   ├── proxmox_vm/       # VM module
│   │   ├── main.tf
│   │   └── variables.tf
│   └── rancher_cluster/  # Rancher installation module
│       ├── main.tf
│       └── outputs.tf
└── environments/
    ├── manager/          # Manager cluster environment
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── backend.tf
    │   └── terraform.tfvars.example
    └── nprd-apps/        # NPRD-Apps cluster environment
        ├── main.tf
        ├── variables.tf
        ├── backend.tf
        └── terraform.tfvars.example
```

## Support

For issues or improvements, refer to:
- [Telmate Proxmox Provider](https://github.com/Telmate/proxmox-terraformer)
- [Rancher Documentation](https://rancher.com/docs/)
- [Terraform Documentation](https://www.terraform.io/docs/)
