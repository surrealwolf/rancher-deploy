# Project Summary

## Rancher Cluster on Proxmox - Terraform Configuration

Complete Infrastructure-as-Code solution for deploying a Rancher management cluster and NPRD-Apps worker cluster on Proxmox.

## Project Structure

```
rancher/
├── README.md                    # Project overview and architecture
├── QUICKSTART.md               # 5-minute quick start guide
├── INFRASTRUCTURE.md           # Detailed setup and troubleshooting
├── Makefile                    # Command shortcuts
├── .gitignore                  # Git ignore rules
├── setup.sh                    # Interactive setup wizard
│
├── terraform/                  # Terraform root module
│   ├── provider.tf            # Provider configuration
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── main.tf                # Main infrastructure
│   │
│   ├── modules/
│   │   ├── proxmox_vm/        # VM provisioning module
│   │   │   ├── main.tf
│   │   │   └── variables.tf
│   │   │
│   │   └── rancher_cluster/   # Rancher installation module
│   │       ├── main.tf
│   │       └── outputs.tf
│   │
│   └── environments/
│       ├── manager/           # Manager cluster environment
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── backend.tf
│       │   └── terraform.tfvars.example
│       │
│       └── nprd-apps/         # NPRD-Apps cluster environment
│           ├── main.tf
│           ├── variables.tf
│           ├── backend.tf
│           └── terraform.tfvars.example
│
└── scripts/
    ├── install-rke2.sh        # RKE2 installation script
    └── configure-kubeconfig.sh # Kubeconfig setup script
```

## Key Features

✅ **Two-Cluster Architecture**
- Rancher Manager cluster (3 nodes)
- NPRD-Apps worker cluster (3 nodes)

✅ **Infrastructure Automation**
- Proxmox VM provisioning
- Automated networking
- SSH-based provisioning

✅ **Kubernetes Ready**
- RKE2 installation scripts
- Kubeconfig management
- Multi-cluster access

✅ **Rancher Deployment**
- cert-manager installation
- Rancher server on manager
- Cluster registration

✅ **Developer Friendly**
- Makefile for common tasks
- Interactive setup wizard
- Example configurations
- Comprehensive documentation

## Quick Commands

```bash
# Check prerequisites
make check-prereqs

# Initialize and deploy manager cluster
make plan-manager
make apply-manager

# Initialize and deploy NPRD-Apps cluster
make plan-nprd
make apply-nprd

# Validate configurations
make validate

# Format Terraform files
make fmt

# Destroy infrastructure
make destroy-all
```

## Cluster Specifications

### Manager Cluster
- **Nodes**: 3
- **CPU**: 4 cores per node
- **Memory**: 8 GB per node
- **Disk**: 100 GB per node
- **Network**: 192.168.1.0/24
- **Components**:
  - RKE2 Kubernetes
  - cert-manager
  - Rancher Server
  - Monitoring stack

### NPRD-Apps Cluster
- **Nodes**: 3
- **CPU**: 8 cores per node
- **Memory**: 16 GB per node
- **Disk**: 150 GB per node
- **Network**: 192.168.2.0/24
- **Components**:
  - RKE2 Kubernetes
  - Rancher Cluster Agent
  - Registered to Manager

## Prerequisites

### Local Machine
- Terraform >= 1.0
- kubectl (recommended)
- helm (recommended)
- SSH client
- curl/wget

### Proxmox
- Proxmox VE 6.4+
- API token with VM management permissions
- Ubuntu 22.04 LTS Cloud-Init template
- Network connectivity

## Deployment Steps

1. **Prepare Proxmox**
   - Create API token
   - Create Ubuntu template
   - Verify network configuration

2. **Configure Terraform**
   - Copy terraform.tfvars.example to terraform.tfvars
   - Update with your Proxmox credentials
   - Verify configuration with `make validate`

3. **Deploy VMs**
   ```bash
   make plan-manager && make apply-manager
   make plan-nprd && make apply-nprd
   ```

4. **Install Kubernetes**
   - Run RKE2 installation on each cluster
   - Configure kubeconfig: `./scripts/configure-kubeconfig.sh`

5. **Deploy Rancher**
   - Install cert-manager
   - Install Rancher Server on manager
   - Register NPRD-Apps cluster

6. **Access Rancher**
   - Open https://rancher.lab.local
   - Login with admin credentials

## File Purposes

### Configuration Files
- `provider.tf` - Proxmox provider setup
- `variables.tf` - Input variable definitions
- `outputs.tf` - Output value definitions
- `main.tf` - Main infrastructure resources

### Modules
- `modules/proxmox_vm/` - Reusable VM provisioning module
- `modules/rancher_cluster/` - Rancher Helm deployment module

### Environments
- `environments/manager/` - Manager cluster specific config
- `environments/nprd-apps/` - NPRD-Apps cluster specific config

### Scripts
- `setup.sh` - Interactive setup wizard
- `scripts/install-rke2.sh` - Kubernetes installation
- `scripts/configure-kubeconfig.sh` - Kubectl configuration

### Documentation
- `README.md` - Architecture and overview
- `QUICKSTART.md` - Quick start guide
- `INFRASTRUCTURE.md` - Detailed setup guide
- `Makefile` - Build targets and utilities

## Customization

### Change Cluster Size

Edit `environments/*/terraform.tfvars`:

```hcl
# Manager cluster - increase resources
cpu_cores    = 8
memory_mb    = 16384

# NPRD-Apps - add more nodes
node_count   = 5
```

### Change Networks

Edit `terraform/main.tf` and update IP ranges:

```hcl
ip_address  = "10.0.1.${100 + i}/24"  # Change 192.168.1
```

### Change Rancher Version

Edit `environments/manager/terraform.tfvars`:

```hcl
rancher_version = "v2.8.0"  # Update version
```

## Troubleshooting

### VMs not provisioning
- Check Proxmox node capacity
- Verify storage pool availability
- Check VM template exists

### Kubernetes not starting
- SSH to node and check RKE2 logs
- Verify CPU/memory requirements
- Check network connectivity

### Rancher not accessible
- Wait 5-10 minutes for initialization
- Check cert-manager status
- Verify DNS resolution

For detailed troubleshooting, see INFRASTRUCTURE.md

## Support Resources

- [Rancher Documentation](https://rancher.com/docs/)
- [RKE2 Documentation](https://docs.rke2.io/)
- [Terraform Proxmox Provider](https://github.com/Telmate/proxmox-terraformer)
- [Proxmox Documentation](https://pve.proxmox.com/wiki/)

## License

This configuration is provided as-is for educational and operational purposes.

## Notes

- All IP addresses are examples; configure for your network
- Adjust resources based on your Proxmox capacity
- Use strong passwords in production
- Configure backup strategy before production use
- Implement monitoring and alerting for production clusters

## Next Steps

1. Review QUICKSTART.md for immediate deployment
2. Read INFRASTRUCTURE.md for detailed setup information
3. Customize terraform.tfvars for your environment
4. Run `make check-prereqs` to verify readiness
5. Deploy with `make plan-manager && make apply-manager`
