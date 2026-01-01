# Architecture Overview

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Proxmox VE 9.x                          │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────┐  ┌──────────────────────────┐   │
│  │  Rancher Manager       │  │  NPRD Apps Cluster       │   │
│  │  Cluster               │  │                          │   │
│  ├────────────────────────┤  ├──────────────────────────┤   │
│  │ VM 401: Manager-1      │  │ VM 404: Apps-1           │   │
│  │ 192.168.1.100         │  │ 192.168.1.110           │   │
│  │ 4 cores, 8GB RAM       │  │ 4 cores, 8GB RAM         │   │
│  ├────────────────────────┤  ├──────────────────────────┤   │
│  │ VM 402: Manager-2      │  │ VM 405: Apps-2           │   │
│  │ 192.168.1.101         │  │ 192.168.1.111           │   │
│  │ 4 cores, 8GB RAM       │  │ 4 cores, 8GB RAM         │   │
│  ├────────────────────────┤  ├──────────────────────────┤   │
│  │ VM 403: Manager-3      │  │ VM 406: Apps-3           │   │
│  │ 192.168.1.102         │  │ 192.168.1.112           │   │
│  │ 4 cores, 8GB RAM       │  │ 4 cores, 8GB RAM         │   │
│  └────────────────────────┘  └──────────────────────────┘   │
│           │                            │                    │
│           └───────────────┬────────────┘                    │
│                           │                                 │
│                   ┌───────▼────────┐                        │
│                   │  VLAN 14       │                        │
│                   │  192.168.1.0/24                        │
│                   └────────────────┘                        │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Network Architecture

### VLAN Configuration

- **VLAN ID**: 14
- **Network**: 192.168.1.0/24
- **Gateway**: 192.168.1.1

### IP Address Allocation

| Cluster | Nodes | IP Range | Hostnames |
|---------|-------|----------|-----------|
| Rancher Manager | 3 | 192.168.1.100-102 | rancher-manager-{1,2,3} |
| NPRD Apps | 3 | 192.168.1.110-112 | nprd-apps-{1,2,3} |

### Network Interfaces

Each VM has:
- **net0**: virtio, bridge=vmbr0, tag=14 (VLAN tagged)
- Network configured via cloud-init
- DNS resolvers: 192.168.1.1, 192.168.1.2
- Domain: example.com (configurable)

## Storage Architecture

### Storage Configuration

- **Proxmox Storage**: local-vm-zfs (configurable)
- **Disk Type**: scsi0 (virtio for network)
- **Disk Size**: 20GB per VM
- **Total Storage**: 120GB (6 VMs × 20GB)

### VM Templates

- **Template ID**: 400 (Ubuntu 22.04 LTS)
- **OS**: Linux with Cloud-Init support
- **Cloud-Init User**: ubuntu
- **SSH Access**: Configured via cloud-init

## Kubernetes Deployment Model

### Rancher Manager Cluster

- **Kubernetes Distribution**: K3s (typical for Rancher)
- **Purpose**: Runs Rancher management plane
- **Features**:
  - Cluster API management
  - Application lifecycle management
  - Multi-cluster monitoring and logging
  - Upstream cluster management

### NPRD Apps Cluster

- **Purpose**: Hosts non-production applications
- **Connection**: Registered to Rancher manager cluster
- **Resources**: Isolated from production workloads

## Infrastructure as Code

### Terraform Module Structure

```
terraform/
├── main.tf                 # Cluster definitions
├── provider.tf             # Provider configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output definitions
└── modules/
    └── proxmox_vm/
        ├── main.tf         # VM resource definition
        └── variables.tf    # VM-level variables
```

### Provider: dataknife/pve v1.0.0

**Advantages over telmate/proxmox:**
- Reliable task polling with exponential backoff retry
- Better error handling and diagnostics
- Improved cloud-init integration
- Full Proxmox VE 9.x support
- Configurable debug logging (PROXMOX_LOG_LEVEL)

## Deployment Flow

```
1. Terraform Init
   └─ Download providers and modules

2. VM Creation (per-cluster)
   ├─ Clone template to VM 401-403 (Manager) or 404-406 (Apps)
   ├─ Update memory, CPU cores, disk
   ├─ Wait for cloud-init completion
   └─ Configure networking via cloud-init

3. Cluster Orchestration
   ├─ Manager cluster created first
   ├─ NPRD apps cluster waits for manager completion
   └─ Explicit depends_on ensures proper sequencing

4. Output
   ├─ Manager cluster IPs
   ├─ Apps cluster IPs
   └─ Ready for Kubernetes/Rancher deployment
```

## Scalability Considerations

### Adding More Nodes

To add nodes to either cluster, modify `terraform/main.tf`:

```hcl
# Add more nodes to rancher_manager (default: 3)
for_each = toset(["manager-1", "manager-2", "manager-3", "manager-4"])
```

### Using Multiple Proxmox Nodes

Distribute VMs across Proxmox cluster nodes:

```hcl
proxmox_node = "pve${(i % 3) + 1}"  # Rotate between pve1, pve2, pve3
```

### Storage Pooling

Utilize Proxmox storage redundancy:
- ZFS pool for performance
- Backup storage for snapshots
- Consider RAID configuration

## Security Considerations

- VMs isolated to VLAN 14
- SSH key-based authentication only
- Cloud-init hardens cloud-user account
- Proxmox API token with minimal permissions
- TLS certificate verification (non-insecure by default)

## Performance Metrics

### Expected Deployment Times

| Operation | Duration |
|-----------|----------|
| Single VM creation (clone + config) | 20-30s |
| 3-node cluster | 1-1.5 minutes |
| All 6 VMs (sequential) | 2-3 minutes |
| All 6 VMs (parallel with limit) | 1-2 minutes |

### Resource Utilization

- **Total CPU**: 24 cores (6 VMs × 4 cores)
- **Total RAM**: 48GB (6 VMs × 8GB)
- **Total Storage**: 120GB (6 VMs × 20GB)

## Disaster Recovery

### Backup Strategy

1. **VM Snapshots**: Create Proxmox snapshots before major changes
2. **Terraform State**: Backup terraform.tfstate securely
3. **Configuration**: Version control all Terraform files

### Recovery Procedures

- **VM Failure**: Replace VM and rejoin cluster
- **Cluster Failure**: Terraform apply to recreate from state
- **Complete Loss**: Rebuild from terraform configuration

## Related Documentation

- [GETTING_STARTED.md](GETTING_STARTED.md) - Quick start
- [TERRAFORM_GUIDE.md](TERRAFORM_GUIDE.md) - Deployment guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Issues and fixes
