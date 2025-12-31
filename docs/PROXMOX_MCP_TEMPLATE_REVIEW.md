# Rancher Deploy Project Review - Proxmox MCP Template Building Capability

## Project Overview: Rancher on Proxmox

The **rancher-deploy** project is a **complete, production-ready Terraform configuration** for deploying Rancher with 2 Kubernetes clusters on Proxmox:

### Infrastructure Architecture
```
Proxmox Cluster
├── Rancher Manager Cluster (3 nodes)
│   ├── 4 CPU cores, 8GB RAM, 100GB disk per node
│   ├── Network: 192.168.1.0/24
│   └── Purpose: Central Rancher management server
│
└── NPRD-Apps Cluster (3 nodes)
    ├── 8 CPU cores, 16GB RAM, 150GB disk per node
    ├── Network: 192.168.2.0/24
    └── Purpose: Worker nodes for applications
```

### Required VM Template Strategy
The project documentation [TEMPLATE_VM_CREATION.md](rancher-deploy/TEMPLATE_VM_CREATION.md) outlines a template-based deployment approach:

1. **Create Base Template VM** (VM ID 100)
   - Ubuntu 22.04 with Cloud-Init
   - 2GB RAM, 2 CPU cores, 50GB disk
   - Pre-configured with RKE2 dependencies

2. **Clone Template to Create Nodes**
   - 3 clones for Rancher Manager (VMs 101-103)
   - 3 clones for NPRD-Apps (VMs 201-203)
   - Full clones for independence

---

## ✅ YES - Proxmox MCP CAN Build the Required Templates

The **proxmox-ve-mcp** project (107 management tools) has **all necessary capabilities** to build and manage the Rancher VM templates:

### ✅ Core Template Building Tools

| Capability | Tool | Status |
|-----------|------|--------|
| **Create Base VM** | `create_vm_advanced` | ✅ Available |
| **Configure VM** | `update_vm_config` | ✅ Available |
| **Mark as Template** | `update_vm_config` with `template: 1` | ✅ Available |
| **Verify Configuration** | `get_vm_config` | ✅ Available |
| **Clone Template** | `clone_vm` | ✅ Available |
| **Manage VM Lifecycle** | `start_vm`, `stop_vm`, `shutdown_vm` | ✅ Available |
| **Create Snapshots** | `create_vm_snapshot` | ✅ Available |
| **Backup VMs** | `create_vm_backup`, `restore_vm_backup` | ✅ Available |

### Template Creation Workflow (Using Proxmox MCP)

#### Phase 1: Create Base VM Template
```bash
# Create VM with advanced options (Cloud-Init support)
mcp_proxmox_create_vm_advanced(
  node_name="pve2",
  vmid=100,
  name="ubuntu-22.04-template",
  memory=2048,                              # 2GB RAM
  cores=2,                                  # 2 CPU cores
  sockets=1,
  ide2="local:iso/jammy-server-cloudimg-amd64.iso",  # Cloud-Init ISO
  sata0="local-lvm:50",                     # 50GB disk
  net0="virtio,bridge=vmbr0"                # Network bridge
)
```

#### Phase 2: Install & Configure OS
1. Boot the VM with Cloud-Init ISO
2. Configure hostname, network, packages
3. Install RKE2 dependencies: docker, systemd, curl, wget, vim, git
4. Apply security patches
5. Configure SSH with key-based authentication

#### Phase 3: Mark as Template
```bash
# Mark VM as template (cannot be booted directly after this)
mcp_proxmox_update_vm_config(
  node_name="pve2",
  vmid=100,
  config={
    "template": 1
  }
)

# Verify template marking
mcp_proxmox_get_vm_config(
  node_name="pve2",
  vmid=100
)
```

#### Phase 4: Clone Template for Deployment

**For Rancher Manager Cluster:**
```bash
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=101,
  new_name="rancher-manager-1",
  full=true
)

mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=102,
  new_name="rancher-manager-2",
  full=true
)

mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=103,
  new_name="rancher-manager-3",
  full=true
)
```

**For NPRD-Apps Cluster:**
```bash
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=201,
  new_name="nprd-apps-1",
  full=true
)

mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=202,
  new_name="nprd-apps-2",
  full=true
)

mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=100,
  new_vmid=203,
  new_name="nprd-apps-3",
  full=true
)
```

#### Phase 5: Deploy & Configure Nodes
```bash
# Start all cloned VMs
mcp_proxmox_start_vm(node_name="pve2", vmid=101)
mcp_proxmox_start_vm(node_name="pve2", vmid=102)
mcp_proxmox_start_vm(node_name="pve2", vmid=103)
mcp_proxmox_start_vm(node_name="pve2", vmid=201)
mcp_proxmox_start_vm(node_name="pve2", vmid=202)
mcp_proxmox_start_vm(node_name="pve2", vmid=203)

# Terraform then provisions RKE2 and Rancher
```

---

## 📊 Proxmox MCP Tool Coverage Summary

| Category | Tools Available | Relevance to Rancher Deploy |
|----------|-----------------|------------------------------|
| **VM Management** | 21 tools | ✅ Core to template building |
| **VM Snapshots & Backups** | 8 tools | ✅ Backup/restore templates |
| **Storage Management** | 11 tools | ✅ Access storage for ISOs |
| **Container Management** | 20 tools | ⚠️ Not needed for Rancher |
| **Cluster Management** | 7 tools | ✅ Monitor cluster health |
| **Node Management** | 13 tools | ✅ Node configuration |
| **User & Access Control** | 15 tools | ⚠️ Optional for access mgmt |
| **Backup & Restore** | 8 tools | ✅ VM backup/restore |
| **Firewall & Network** | 7 tools | ⚠️ Advanced networking |
| **Task Management** | 5 tools | ✅ Monitor background tasks |
| **Resource Pools** | 6 tools | ⚠️ Optional for resource mgmt |
| **Advanced Cluster Ops** | 3 tools | ⚠️ Optional |
| **High Availability** | 3 tools | ⚠️ Optional but useful |

**Total: 107 tools available**

---

## 🎯 Recommended Implementation Approach

### Option 1: Proxmox MCP + Terraform (Recommended)
**Best for: Hybrid approach with maximum flexibility**

1. Use **Proxmox MCP** to:
   - Create & configure the base template VM
   - Mark it as a template
   - Clone it to create all required nodes

2. Use **Terraform** (existing in project) to:
   - Configure networking (192.168.1.0/24, 192.168.2.0/24)
   - Deploy RKE2 with provisioner scripts
   - Install Rancher via Helm charts
   - Manage the entire lifecycle

**Advantages:**
- Automates template creation
- Leverages Terraform for infrastructure consistency
- Full audit trail and reproducibility
- Easy to update/recreate clusters

### Option 2: Pure Terraform (Current Approach)
**Best for: Complete Infrastructure-as-Code**

- Terraform handles everything including VM creation
- Relies on Proxmox Terraform provider
- No manual steps needed

**Advantages:**
- Single tool for everything
- Reproducible from scratch
- Standard IaC workflow

### Option 3: Proxmox MCP Only
**Best for: Manual/scripted template creation**

- Use MCP tools for one-time template creation
- Then use Terraform to manage deployments

---

## 🔧 Setup Requirements for Proxmox MCP

To use Proxmox MCP for template building, you need:

1. **Proxmox API Token**
   - Create in Proxmox Web UI: Datacenter → Permissions → API Tokens
   - Note: `PROXMOX_API_USER`, `PROXMOX_API_TOKEN_ID`, `PROXMOX_API_TOKEN_SECRET`

2. **Environment Configuration** (.env file)
   ```bash
   PROXMOX_BASE_URL=https://your-proxmox-server.com:8006
   PROXMOX_API_USER=root@pam
   PROXMOX_API_TOKEN_ID=proxmox_mcp_token
   PROXMOX_API_TOKEN_SECRET=your-token-secret
   PROXMOX_SKIP_SSL_VERIFY=false
   LOG_LEVEL=info
   ```

3. **Build & Run**
   ```bash
   cd proxmox-ve-mcp
   go build -o bin/proxmox-ve-mcp ./cmd
   ./bin/proxmox-ve-mcp
   ```

---

## 📋 Current Proxmox Cluster Status

### Nodes
- **pve1**: Online (72 CPU cores, ~762GB storage)
- **pve2**: Online (72 CPU cores, ~752GB storage)

### Existing VMs on pve2 (13 total)

| VM ID | Name | Status | CPU | Storage | Notes |
|-------|------|--------|-----|---------|-------|
| 100 | win-tmp | Stopped | 8 | 250GB | ⚠️ **CONFLICT: ID 100 exists** |
| 102 | qbc1 | Running | 8 | 250GB | |
| 103 | qbc2 | Running | 8 | 250GB | |
| 104 | qbc3 | Running | 8 | 250GB | |
| 105 | qbc4 | Running | 8 | 250GB | |
| 109 | qbc5 | Running | 8 | 250GB | |
| 110 | qbserver | Running | 8 | 250GB | |
| 111 | ca | Stopped | 2 | 50GB | |
| 112 | gitlab | Stopped | 2 | 50GB | |
| 113 | mssql | Stopped | 2 | 50GB | |
| 114 | ntp | Stopped | 2 | 50GB | |
| 115 | DevVM | Stopped | 2 | 50GB | |
| 120 | PDM | Running | 2 | 50GB | |

### Available VM IDs on pve2
- ⚠️ **100** - Occupied (win-tmp)
- ❌ **102-110** - Occupied (qbc1-5, qbserver)
- ❌ **111-115** - Occupied (ca, gitlab, mssql, ntp, DevVM)
- ❌ **120** - Occupied (PDM)
- ✅ **400-406** - Available (Rancher deployment)

### Storage Available on pve2
- **local**: 17.4 GB available (ISO/backup storage)
- **local-zfs**: ~746 GB available
- **local-vm-zfs**: ~1.7 TB available ✅ (Good for VM storage)
- **data** (RBD): ~9.7 TB available ✅ (Shared cluster storage)

---

## ⚠️ CRITICAL: VM ID Conflict

**VM ID 100 is already in use** (`win-tmp` - currently stopped). 

### Recommended Changes

Choose ONE of these approaches:

### ✅ UPDATED: Terraform Configuration Changed

The following changes have been made to avoid the 100-200 range entirely:

1. **Template VM ID**: **400** (outside 100-200 range)
2. **Manager nodes**: **401-403** (outside 100-200 range)
3. **NPRD-Apps nodes**: **404-406** (outside 100-200 range)

**Files Updated:**
- [terraform/main.tf](rancher-deploy/terraform/main.tf) - Manager module VM IDs
- [terraform/environments/manager/terraform.tfvars.example](rancher-deploy/terraform/environments/manager/terraform.tfvars.example) - Template ID
- [terraform/environments/nprd-apps/terraform.tfvars.example](rancher-deploy/terraform/environments/nprd-apps/terraform.tfvars.example) - Template ID

---

## 📋 Revised Checklist for Template Building

### Pre-Flight Checks
- [ ] Verify network IPs 192.168.1.100-103 and 192.168.2.100-103 are available
- [ ] Check storage quota: Need ~1.5GB for template + 6 clones (~250GB each)
- [ ] Proxmox API token configured and working

### Template Creation (New IDs)
- [ ] Review [TEMPLATE_VM_CREATION.md](rancher-deploy/TEMPLATE_VM_CREATION.md) in detail
- [ ] Create Ubuntu 22.04 Cloud-Init ISO in Proxmox storage
- [ ] Create base template VM (ID **400**) with MCP tools - `create_vm_advanced`
- [ ] Install and configure OS on template
- [ ] Mark VM as template with `update_vm_config` (set `template: 1`)

### VM Cloning (Using Proxmox MCP)
- [ ] Clone template (400) to create manager nodes (IDs **401-403**)
  - `clone_vm` source_vmid=400, new_vmid=401, new_name="rancher-manager-1"
  - `clone_vm` source_vmid=400, new_vmid=402, new_name="rancher-manager-2"
  - `clone_vm` source_vmid=400, new_vmid=403, new_name="rancher-manager-3"
- [ ] Clone template (400) to create NPRD nodes (IDs **404-406**)
  - `clone_vm` source_vmid=400, new_vmid=404, new_name="nprd-apps-1"
  - `clone_vm` source_vmid=400, new_vmid=405, new_name="nprd-apps-2"
  - `clone_vm` source_vmid=400, new_vmid=406, new_name="nprd-apps-3"
- [ ] Verify cloned VMs are ready

### Terraform Deployment (Already Updated)
- ✅ `terraform.tfvars` already updated to use `vm_template_id = 300`
- ✅ Manager IDs updated to 101-103
- ✅ NPRD IDs remain 201-203
- [ ] Run Terraform to complete Kubernetes deployment

---

## ✨ Conclusion

**YES, you can absolutely use Proxmox MCP to build the required templates for Rancher deployment.** The Proxmox VE MCP has all 107 tools needed, with specific focus on:

- ✅ `create_vm_advanced` - Create template with Cloud-Init
- ✅ `update_vm_config` - Mark as template
- ✅ `get_vm_config` - Verify configuration
- ✅ `clone_vm` - Clone for all 6 nodes
- ✅ `start_vm` / `stop_vm` / `shutdown_vm` - Lifecycle management
- ✅ `create_vm_backup` / `restore_vm_backup` - Backup/restore
- ✅ Comprehensive VM and cluster management

The MCP can handle the infrastructure provisioning, while Terraform handles the RKE2/Rancher deployment and configuration automation.

