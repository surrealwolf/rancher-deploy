# Template VM Creation - Implementation Guide

## Step 1: Create Base Template VM (ID 400)

Using Proxmox MCP `create_vm_advanced` tool:

```bash
# Create Ubuntu 22.04 template with Cloud-Init support
mcp_proxmox_create_vm_advanced(
  node_name="pve2",
  vmid=400,
  name="ubuntu-22.04-template",
  memory=2048,                                    # 2GB RAM
  cores=2,                                        # 2 CPU cores
  sockets=1,
  ide2="local:iso/jammy-server-cloudimg-amd64.iso",  # Cloud-Init ISO
  sata0="local-vm-zfs:50",                       # 50GB disk on fast storage
  net0="virtio,bridge=vmbr0"                     # Network
)
```

### Alternative (if ISO not available):
May need to download Ubuntu Cloud Image first:
```bash
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

---

## Step 2: Boot and Configure VM

1. **Start the VM**
   ```bash
   mcp_proxmox_start_vm(node_name="pve2", vmid=400)
   ```

2. **Access console** (via Proxmox Web UI or SSH once it has an IP)

3. **Installation Steps:**
   - Complete Cloud-Init setup
   - Configure hostname: `ubuntu-template`
   - Set DHCP networking
   - Enable SSH with key-based auth
   - Install packages:
     ```bash
     sudo apt update
     sudo apt install -y curl wget vim git systemd
     ```
   - Install RKE2 dependencies:
     ```bash
     sudo apt install -y docker.io
     sudo usermod -aG docker ubuntu
     ```
   - Apply security patches:
     ```bash
     sudo apt upgrade -y
     ```

4. **Clean up for template:**
   ```bash
   sudo apt clean
   sudo apt autoclean
   sudo truncate -s 0 /var/log/*
   ```

5. **Shutdown gracefully:**
   ```bash
   mcp_proxmox_shutdown_vm(node_name="pve2", vmid=400)
   ```

---

## Step 3: Mark VM as Template

Once VM is fully configured and shut down:

```bash
mcp_proxmox_update_vm_config(
  node_name="pve2",
  vmid=400,
  config={
    "template": 1
  }
)
```

### Verify template marking:
```bash
mcp_proxmox_get_vm_config(node_name="pve2", vmid=400)
```

Expected output should show: `"template": 1`

---

## Step 4: Clone Template to Manager Nodes

Create 3 clones for Rancher Manager cluster:

```bash
# Manager Node 1
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=401,
  new_name="rancher-manager-1",
  full=true
)

# Manager Node 2
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=402,
  new_name="rancher-manager-2",
  full=true
)

# Manager Node 3
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=403,
  new_name="rancher-manager-3",
  full=true
)
```

---

## Step 5: Clone Template to NPRD-Apps Nodes

Create 3 clones for NPRD-Apps worker cluster:

```bash
# NPRD Node 1
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=404,
  new_name="nprd-apps-1",
  full=true
)

# NPRD Node 2
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=405,
  new_name="nprd-apps-2",
  full=true
)

# NPRD Node 3
mcp_proxmox_clone_vm(
  node_name="pve2",
  source_vmid=400,
  new_vmid=406,
  new_name="nprd-apps-3",
  full=true
)
```

---

## Step 6: Verify Cloned VMs

Check that all 6 clones were created successfully:

```bash
mcp_proxmox_get_vms(node_name="pve2")
```

Expected VMs:
- ✅ 400 (template, stopped)
- ✅ 401 (rancher-manager-1, stopped)
- ✅ 402 (rancher-manager-2, stopped)
- ✅ 403 (rancher-manager-3, stopped)
- ✅ 404 (nprd-apps-1, stopped)
- ✅ 405 (nprd-apps-2, stopped)
- ✅ 406 (nprd-apps-3, stopped)

---

## Step 7: Deploy with Terraform

Once all VMs are created:

```bash
cd /home/lee/git/rancher-deploy/terraform/environments/manager
terraform init
terraform plan
terraform apply

cd ../nprd-apps
terraform init
terraform plan
terraform apply
```

---

## Troubleshooting

### Template creation fails
- Check storage space on `local-vm-zfs`: needs ~50GB
- Verify Cloud-Init ISO exists at `local:iso/jammy-server-cloudimg-amd64.iso`
- Check Proxmox MCP is connected and authenticated

### Clone fails
- Verify source template (400) exists and is marked as template
- Check enough storage space for clones (50GB each)
- Check VM IDs 401-406 don't already exist

### VM won't boot from clone
- May need to configure boot order in clone
- Verify network bridge `vmbr0` exists
- Check Cloud-Init cloud-config settings

