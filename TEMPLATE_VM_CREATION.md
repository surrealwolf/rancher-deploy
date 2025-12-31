# Template VM Creation Guide for Rancher Deployment

## Overview

This guide explains how to use the Proxmox VE MCP tools to create, configure, and deploy template VMs for the Rancher Kubernetes infrastructure.

## Quick Reference: New Tools Available

These tools have been added to support template VM creation:

1. **`update_vm_config`** - Update VM configuration and mark as template
2. **`get_vm_config`** - Retrieve full VM configuration
3. **`update_container_config`** - Update LXC container configuration
4. **`get_container_config`** - Retrieve full container configuration

## Architecture: What We're Building

```
Proxmox Cluster
├── VM Template (VM ID 100)
│   └── ubuntu-22.04-template
│       ├── Cloned for Rancher Manager (3 nodes)
│       │   ├── rancher-manager-1 (VM 101)
│       │   ├── rancher-manager-2 (VM 102)
│       │   └── rancher-manager-3 (VM 103)
│       └── Cloned for NPRD-Apps (3 nodes)
│           ├── nprd-apps-1 (VM 201)
│           ├── nprd-apps-2 (VM 202)
│           └── nprd-apps-3 (VM 203)
```

## Template Creation Workflow

### Phase 1: Create Base VM

Create a new VM with Cloud-Init support:

```bash
# Using Proxmox MCP - create_vm_advanced
proxmox_create_vm_advanced(
  node_name="pve2",
  vmid=100,
  name="ubuntu-22.04-template",
  memory=2048,              # 2GB RAM
  cores=2,                  # 2 CPU cores
  sockets=1,
  ide2="local:iso/jammy-server-cloudimg-amd64.iso",  # Cloud-Init ISO
  sata0="local-lvm:50",     # 50GB disk
  net0="virtio,bridge=vmbr0"
)
```

**Proxmox Commands (Manual Alternative):**
```bash
# SSH to Proxmox node
qm create 100 --name ubuntu-22.04-template \
  --memory 2048 --cores 2 --sockets 1 --net0 virtio,bridge=vmbr0

# Import Ubuntu Cloud Image
qm importdisk 100 jammy-server-cloudimg-amd64.img local-lvm
qm set 100 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-100-disk-0
qm set 100 --ide2 local-lvm:cloudinit
qm set 100 --boot c --bootdisk scsi0
qm set 100 --serial0 socket
```

### Phase 2: Install and Configure OS

1. Boot the VM with Cloud-Init ISO
2. Configure:
   - Hostname (will be overridden per clone)
   - Network (DHCP - will be configured via Cloud-Init per clone)
   - Basic packages: curl, wget, vim, git
   - SSH server with key-based auth
   - RKE2 dependencies: docker, systemd, various libs
3. Apply security patches
4. Verify all systems work

### Phase 3: Mark as Template

Once fully configured and tested:

```bash
# Using Proxmox MCP - update_vm_config
proxmox_update_vm_config(
  node_name="pve2",
  vmid=100,
  config={
    "template": 1
  }
)
```

**Proxmox Command (Manual Alternative):**
```bash
qm set 100 --template 1
```

⚠️ **Important**: Once marked as template, the VM cannot be booted directly!

### Phase 4: Verify Template Configuration

```bash
# Check template configuration
proxmox_get_vm_config(
  node_name="pve2",
  vmid=100
)
```

Expected output should show `"template": 1` in the config.

## Deploying from Template

### Clone for Rancher Manager Cluster

```bash
# Clone template 3 times for control plane nodes
proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=101,
  new_name="rancher-manager-1",
  full=true
)

proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=102,
  new_name="rancher-manager-2",
  full=true
)

proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=103,
  new_name="rancher-manager-3",
  full=true
)
```

### Clone for NPRD-Apps Cluster

```bash
# Clone template 3 times for worker nodes
proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=201,
  new_name="nprd-apps-1",
  full=true
)

proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=202,
  new_name="nprd-apps-2",
  full=true
)

proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=203,
  new_name="nprd-apps-3",
  full=true
)
```

### Boot and Configure Clones

After cloning:

1. Boot each cloned VM
2. Configure via Cloud-Init:
   - Hostname: rancher-manager-1, rancher-manager-2, etc.
   - IP address: 192.168.1.100-102 (manager), 192.168.2.100-102 (nprd-apps)
   - Gateway and DNS
3. Install RKE2
4. Configure cluster

## Terraform Integration

These new MCP tools complement your existing Terraform configuration:

### Current Terraform Setup
- Uses `telmate/proxmox` provider to clone template
- Requires template with ID 100 to exist

### Enhanced Workflow

**Option 1: Manual + Terraform**
1. Use Proxmox MCP (or manual steps) to create and test template
2. Use Terraform to clone at scale for production

**Option 2: Full MCP Automation**
1. Create template via MCP
2. Clone via MCP (alternative to Terraform)
3. Configure via Cloud-Init

**Option 3: Hybrid**
1. Create template interactively with MCP
2. Test thoroughly
3. Use Terraform for reproducible production deployment

## Configuration File Updates

Update your `terraform.tfvars` files to match cloned VM IDs:

### Manager Environment
```hcl
template_id = 100

manager_configs = [
  {
    vmid     = 101
    hostname = "rancher-manager-1"
    ip       = "192.168.1.100"
  },
  {
    vmid     = 102
    hostname = "rancher-manager-2"
    ip       = "192.168.1.101"
  },
  {
    vmid     = 103
    hostname = "rancher-manager-3"
    ip       = "192.168.1.102"
  },
]
```

### NPRD-Apps Environment
```hcl
template_id = 100

nprd_configs = [
  {
    vmid     = 201
    hostname = "nprd-apps-1"
    ip       = "192.168.2.100"
  },
  {
    vmid     = 202
    hostname = "nprd-apps-2"
    ip       = "192.168.2.101"
  },
  {
    vmid     = 203
    hostname = "nprd-apps-3"
    ip       = "192.168.2.102"
  },
]
```

## Troubleshooting

### Template Won't Mark
- Ensure VM is stopped before marking as template
- Check VM has valid disk configuration
- Verify node has sufficient resources

### Clone Fails
- Verify template exists and is marked as template
- Check target VMID is unique (not already in use)
- Ensure sufficient storage space

### Boot Issues After Clone
- Cloud-Init may take time to initialize
- Check VM serial console for boot messages
- Verify network configuration
- Check system logs: `systemctl status`

## Next Steps

After template creation:

1. ✅ Template VM created and marked (this guide)
2. ⏭️ Terraform deployment via `terraform apply`
3. ⏭️ RKE2 installation (via scripts in project)
4. ⏭️ Rancher setup and configuration
5. ⏭️ Application deployment

## Tools Reference

### Proxmox MCP Tools Used

- **update_vm_config** - Mark VM as template
- **get_vm_config** - Verify template configuration
- **clone_vm** - Create instances from template
- **create_vm_advanced** - Create base VM
- **get_vm_status** - Monitor VM status
- **get_vms** - List all VMs

### Proxmox API Endpoints (for reference)

- `PUT /nodes/{node}/qemu/{vmid}/config` - Update VM config
- `GET /nodes/{node}/qemu/{vmid}/config` - Get VM config
- `POST /nodes/{node}/qemu/{vmid}/clone` - Clone VM
- `POST /nodes/{node}/qemu` - Create VM

## Resources

- [VM Template Creation Skill](/proxmox-ve-mcp/.github/skills/vm-template-creation/SKILL.md)
- [Virtual Machine Management Skill](/proxmox-ve-mcp/.github/skills/virtual-machine-management/SKILL.md)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/)
- [Cloud-Init Documentation](https://cloud-init.io/docs/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
