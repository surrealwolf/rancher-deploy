# New Tools Available for Rancher Deployment

## Summary

The Proxmox VE MCP now has **2 new tools** and enhanced documentation for **VM template creation**. These tools enable you to:

1. ✅ Create and configure template VMs using MCP
2. ✅ Mark VMs as templates for cloning
3. ✅ Get and verify VM configurations
4. ✅ Deploy standardized VMs for Rancher clusters

## New Tools

### 1. `update_vm_config` 🆕
Update virtual machine configuration and mark as template.

**Example: Mark VM 100 as Template**
```bash
# Using Proxmox MCP
proxmox_update_vm_config(
  node_name="pve2",
  vmid=100,
  config={"template": 1}
)
```

**Use Cases:**
- Mark VM as template after configuration
- Adjust VM resources (CPU, memory)
- Enable/disable features
- Modify storage or network settings

### 2. `update_container_config` 🆕
Update LXC container configuration.

**Use Cases:**
- Modify container resources
- Update network configuration
- Adjust memory/CPU allocation
- Configuration management

### 3. `get_vm_config` (Enhanced)
Retrieve full VM configuration details.

**Example:**
```bash
proxmox_get_vm_config(
  node_name="pve2",
  vmid=100
)
```

### 4. `get_container_config` (Enhanced)
Retrieve full LXC container configuration.

## Complete Workflow: Template to Cluster

### Phase 1: Create Template (One-time)
```bash
# 1. Create base VM
create_vm_advanced(
  node_name="pve2",
  vmid=100,
  name="ubuntu-22.04-template",
  memory=2048,
  cores=2,
  ide2="local:iso/jammy-server-cloudimg-amd64.iso",
  sata0="local-lvm:50",
  net0="virtio,bridge=vmbr0"
)

# 2. Boot, install OS, configure
#    (Manual or via automated scripts)

# 3. Mark as template
update_vm_config(
  node_name="pve2",
  vmid=100,
  config={"template": 1}
)
```

### Phase 2: Clone for Cluster (Automated)
```bash
# Clone template 6 times
for i in {1..3}; do
  clone_vm(
    node_name="pve2",
    source_vmid=100,
    new_vmid=$((100 + i)),
    new_name="rancher-manager-${i}",
    full=true
  )
done

for i in {1..3}; do
  clone_vm(
    node_name="pve2",
    source_vmid=100,
    new_vmid=$((200 + i)),
    new_name="nprd-apps-${i}",
    full=true
  )
done
```

### Phase 3: Deploy with Terraform
```bash
cd terraform/environments/manager
terraform plan
terraform apply

cd ../nprd-apps
terraform plan
terraform apply
```

## Architecture

```
Template VM (100)
├── Rancher Manager Cluster
│   ├── rancher-manager-1 (101) - Control Plane
│   ├── rancher-manager-2 (102) - Control Plane
│   └── rancher-manager-3 (103) - Control Plane
│
└── NPRD-Apps Cluster
    ├── nprd-apps-1 (201) - Worker Node
    ├── nprd-apps-2 (202) - Worker Node
    └── nprd-apps-3 (203) - Worker Node
```

## Documentation

### Main Guides
1. **[TEMPLATE_VM_CREATION.md](./TEMPLATE_VM_CREATION.md)**
   - Complete template creation workflow
   - Step-by-step instructions
   - Integration with Terraform
   - Troubleshooting guide

2. **[VM Template Creation Skill](/proxmox-ve-mcp/.github/skills/vm-template-creation/SKILL.md)**
   - Comprehensive skill documentation
   - Real-world examples
   - Best practices
   - Configuration options

3. **[Implementation Summary](/proxmox-ve-mcp/IMPLEMENTATION_SUMMARY.md)**
   - Technical implementation details
   - Tool descriptions
   - API endpoints
   - Future enhancements

### Supporting Documentation
- `VM Management Skill` - General VM lifecycle
- `Cluster Management Skill` - Cluster monitoring
- `Disaster Recovery Skill` - Backup/restore

## Quick Reference

### Template Creation
```bash
# Create VM
create_vm_advanced(node="pve2", vmid=100, ...)

# Configure OS and applications
# (Boot and install manually or via scripts)

# Mark as template
update_vm_config(node="pve2", vmid=100, config={"template": 1})

# Verify
get_vm_config(node="pve2", vmid=100)
```

### Template Cloning
```bash
# Clone template
clone_vm(
  node="pve2",
  source_vmid=100,
  new_vmid=101,
  new_name="node-1",
  full=true
)

# Start cloned VM
start_vm(node="pve2", vmid=101)

# Verify
get_vm_status(node="pve2", vmid=101)
```

## Integration Points

### With Terraform
```hcl
# Template VM ID in terraform.tfvars
template_id = 100

# Terraform clones from template for consistent deployments
```

### With Cloud-Init
```yaml
# Configure per-clone:
- Hostname
- IP address / DHCP
- DNS settings
- User accounts
- SSH keys
```

### With Proxmox API
```
PUT /nodes/{node}/qemu/{vmid}/config  # update_vm_config
GET /nodes/{node}/qemu/{vmid}/config  # get_vm_config
POST /nodes/{node}/qemu/{vmid}/clone  # clone_vm
```

## Benefits

✅ **Automation** - Scripted template creation and deployment
✅ **Consistency** - Standardized VM configurations
✅ **Speed** - Fast cloning instead of full VM creation
✅ **Repeatability** - Same process for multiple environments
✅ **Testability** - Interactive tool testing before production
✅ **Documentation** - Clear, documented workflows

## Key Points

### Templates
- Cannot be started directly
- Must be cloned before use
- Each clone is independent
- Smaller templates clone faster

### Cloning
- Creates full, independent VMs
- Uses VM IDs efficiently
- Preserves all configurations
- Network configured post-clone via Cloud-Init

### Network Configuration
- Manager cluster: 192.168.1.100-102
- NPRD-Apps cluster: 192.168.2.100-102
- Configured via Cloud-Init after cloning
- Can be customized per clone

## What's Next

1. ✅ Tools are ready for use
2. ⏭️ Prepare base template VM
3. ⏭️ Configure template with OS/packages
4. ⏭️ Mark as template using `update_vm_config`
5. ⏭️ Clone 6 VMs for clusters
6. ⏭️ Deploy with Terraform
7. ⏭️ Configure Rancher and Kubernetes

## Support & Questions

See [TEMPLATE_VM_CREATION.md](./TEMPLATE_VM_CREATION.md) for:
- Detailed workflows
- Configuration options
- Troubleshooting tips
- Example commands

See skills documentation for:
- Best practices
- Real-world examples
- Integration patterns
- Performance tips

## Tool Availability

✅ All tools are available in:
- Proxmox VE MCP server (compiled and ready)
- MCP tools interface
- Documentation and guides
- Examples and workflows

**Total MCP Tools**: 62 (including 2 new, 2 enhanced)
**Build Status**: ✅ Successful
**Documentation**: ✅ Comprehensive

---

**Ready to deploy!** Start with [TEMPLATE_VM_CREATION.md](./TEMPLATE_VM_CREATION.md)
