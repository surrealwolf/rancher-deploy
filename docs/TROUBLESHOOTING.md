# Troubleshooting Guide

Common issues and solutions when deploying Rancher clusters on Proxmox.

## Terraform Issues

### Issue: "terraform init" fails with provider error

**Error:**
```
Error: Failed to query available provider packages...
```

**Solution:**
1. Verify internet connectivity
2. Ensure Terraform version >= 1.0
3. Clear cache: `rm -rf .terraform`
4. Retry `terraform init`

### Issue: Terraform plan shows no changes but nothing deployed

**Symptom:** `terraform plan` succeeds but `terraform apply` does nothing

**Solution:**
1. Check you're using correct state file: `terraform state list`
2. Verify variables are correctly set: `terraform plan -var-file=terraform.tfvars`
3. If needed, import existing resources: `terraform import pve_qemu.vm <vmid>`

## Proxmox API Issues

### Issue: "API authentication failed" or "403 Forbidden"

**Error:**
```
Error: ... 403 Forbidden
```

**Solutions:**

1. **Verify API token exists:**
   ```bash
   # In Proxmox UI:
   Datacenter → Users → Select user → API Tokens
   ```

2. **Check token permissions:**
   - Ensure token has permissions for:
     - Datastore.Allocate
     - Datastore.Browse
     - Nodes.Shutdown
     - VMs.Allocate
     - VMs.Clone
     - VMs.Console
     - VMs.Config.*

3. **Validate credentials in terraform.tfvars:**
   ```hcl
   proxmox_api_url          = "https://your-proxmox:8006/api2/json"
   proxmox_api_user         = "terraform@pam"
   proxmox_api_token_id     = "your-token-id"
   proxmox_api_token_secret = "your-token-secret"
   ```

4. **Test manually:**
   ```bash
   curl -X GET \
     -H "Authorization: PVEAPIToken=terraform@pam:your-token-id=your-token-secret" \
     https://your-proxmox:8006/api2/json/nodes
   ```

### Issue: "TLS certificate verification failed"

**Error:**
```
Error: ... x509: certificate signed by unknown authority
```

**Solutions:**

**Option 1: Fix certificate (recommended)**
1. Install valid certificate in Proxmox
2. Run Terraform: `terraform apply`

**Option 2: Disable verification (testing only)**
```hcl
# In terraform/variables.tf
variable "proxmox_tls_insecure" {
  default = true  # NOT for production!
}
```

## VM Creation Issues

### Issue: VM creation times out after 2+ minutes

**Symptom:** Terraform times out waiting for VM to be ready

**Solutions:**

1. **Enable debug logging:**
   ```bash
   export PROXMOX_LOG_LEVEL=debug
   terraform apply
   ```

2. **Check Proxmox task history:**
   ```bash
   # In Proxmox UI: Datacenter → Tasks
   # Look for failed clone or config tasks
   ```

3. **Verify VM template exists:**
   ```bash
   # Check template ID matches configuration
   # Proxmox UI: Datacenter → VMs → Look for VM 400 (or your template)
   ```

4. **Check storage space:**
   ```bash
   # Ensure local-vm-zfs has sufficient free space
   # Need: 6 VMs × 20GB = 120GB minimum
   ```

5. **Verify template is properly configured:**
   - Cloud-init drive present
   - Network interface configured
   - SSH public key loaded

### Issue: "VM already exists" error

**Error:**
```
Error: VM already exists
```

**Solutions:**

1. **Check if VM already created:**
   ```bash
   # Proxmox UI: Look for VMs 401-406
   ```

2. **Option A: Delete VMs and retry**
   ```bash
   # In Proxmox UI: Delete VMs 401-406
   terraform apply
   ```

3. **Option B: Import existing VMs**
   ```bash
   # Import VM 401:
   terraform import pve_qemu.vm["rancher-manager-1"] 401
   # Repeat for other VMs 402-406
   ```

### Issue: VMs created but cloud-init not applied

**Symptom:** VMs created but network not configured, can't SSH

**Solutions:**

1. **Check cloud-init status:**
   ```bash
   # SSH to VM (from Proxmox console):
   ssh ubuntu@<vm-console>
   cloud-init status
   cloud-init query
   ```

2. **Check cloud-init logs:**
   ```bash
   # In VM console:
   journalctl -u cloud-init -n 50
   ```

3. **Verify cloud-init data passed:**
   ```bash
   # In VM:
   ls -la /var/lib/cloud/instance/
   ```

4. **Check network configuration:**
   ```bash
   # In VM:
   ip addr show
   netplan status
   ```

## Network Issues

### Issue: VMs can't reach network or no IP address

**Symptom:** VM created but "ip addr show" shows no IPv4

**Solutions:**

1. **Verify VLAN configuration:**
   - Check vmbr0 has VLAN 14 support: `ip link show vmbr0`
   - Ensure vmbr0 configured properly in /etc/network/interfaces

2. **Check cloud-init network config:**
   ```bash
   # In VM:
   cat /etc/netplan/01-netcfg.yaml
   sudo netplan apply
   ip addr show
   ```

3. **Verify DNS resolution:**
   ```bash
   # In VM:
   cat /etc/resolv.conf
   nslookup example.com
   ```

4. **Test gateway reachability:**
   ```bash
   # In VM:
   ping 192.168.1.1
   ```

### Issue: VMs on different clusters can't communicate

**Symptom:** Ping between manager and apps cluster fails

**Solution:**
1. Ensure both use same VLAN 14
2. Check firewall rules (Proxmox or upstream)
3. Verify routing between network segments

## SSH/Connection Issues

### Issue: "Permission denied (publickey)"

**Error:**
```
Permission denied (publickey).
```

**Solutions:**

1. **Verify SSH key path:**
   ```bash
   ls -la ~/.ssh/id_rsa
   ```

2. **Check key in Terraform config:**
   ```bash
   # In terraform.tfvars:
   ssh_private_key = "~/.ssh/id_rsa"  # Correct path?
   ```

3. **Verify public key in VM:**
   ```bash
   # Via Proxmox console:
   cat ~/.ssh/authorized_keys
   # Should contain your public key
   ```

4. **Check SSH permissions:**
   ```bash
   # In VM:
   ls -la ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   chmod 700 ~/.ssh
   ```

5. **Try with verbose output:**
   ```bash
   ssh -v -i ~/.ssh/id_rsa ubuntu@192.168.1.100
   ```

### Issue: Timeout connecting to SSH

**Error:**
```
Connection refused or timeout
```

**Solutions:**

1. **Wait for VM to fully boot:**
   - Cloud-init may take 1-2 minutes
   - Check in Proxmox console if services running

2. **Verify network connectivity:**
   ```bash
   ping 192.168.1.100  # From Proxmox host
   ```

3. **Check SSH service:**
   ```bash
   # Via Proxmox console:
   sudo systemctl status ssh
   ```

4. **Increase wait time in Terraform:**
   ```hcl
   # In modules/proxmox_vm/main.tf
   # Add longer initial delay for cloud-init
   ```

## Kubernetes/Rancher Issues

### Issue: RKE2 installation fails with "latest" version

**Error:**
```
curl: (22) The requested URL returned error: 404
Failed to enable unit: Unit file rke2-server.service does not exist
```

**Root Cause:**
The RKE2 installer cannot download a release called "latest". Only specific version tags (e.g., v1.34.3+rke2r1) are available as downloadable releases.

**Solutions:**

1. **Verify using actual release version:**
   ```hcl
   # In terraform/main.tf, use specific version:
   rke2_version = "v1.34.3+rke2r1"  # CORRECT - actual released version
   rke2_version = "latest"          # WRONG - not a downloadable release
   ```

2. **Check available versions:**
   ```bash
   # Visit GitHub releases page
   curl -s https://api.github.com/repos/rancher/rke2/releases?per_page=10 | jq '.[].tag_name'
   # Or browse: https://github.com/rancher/rke2/tags
   ```

3. **Latest stable version examples:**
   - v1.35.0+rke2r1 (latest)
   - v1.34.3+rke2r1 (stable)
   - v1.33.7+rke2r1 (supported)
   - v1.32.11+rke2r1 (supported)

4. **Update terraform.tfvars if needed:**
   ```hcl
   # terraform/terraform.tfvars
   rke2_version = "v1.34.3+rke2r1"
   ```

5. **Clean state and redeploy:**
   ```bash
   cd terraform
   rm -f terraform.tfstate*
   terraform apply -auto-approve
   ```

**Prevention:**
Always use specific version tags. Check GitHub releases before setting `rke2_version` variable.

### Issue: RKE2 installation script download fails

**Error:**
```
curl: (7) Failed to connect to get.rke2.io port 443: Connection refused
```

**Solutions:**

1. **Check internet connectivity:**
   ```bash
   ping github.com
   curl -I https://get.rke2.io
   ```

2. **Verify GitHub is accessible:**
   ```bash
   # RKE2 uses get.rke2.io which redirects to GitHub releases
   curl -L https://get.rke2.io | head -20
   ```

3. **Check firewall rules:**
   - Proxmox host must allow outbound HTTPS to github.com
   - VMs must allow outbound HTTPS to github.com
   - Test from VM: `curl https://api.github.com`

4. **Retry with increased timeout:**
   ```bash
   # Wait longer for provisioners
   export TF_PLUGIN_LOG=trace
   terraform apply
   ```

### Issue: RKE2 server doesn't start after installation

**Symptom:** Installation script completes but `systemctl status rke2-server` shows failed

**Solutions:**

1. **Check SSH into VM and verify installation:**
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.100
   sudo systemctl status rke2-server
   sudo journalctl -u rke2-server -n 50
   ```

2. **Verify cloud-init completed:**
   ```bash
   cloud-init status
   cloud-init query
   ```

3. **Check system resources:**
   ```bash
   free -h          # RAM available
   df -h /          # Disk space
   nproc             # CPU cores
   ```

4. **Verify RKE2 binary installed:**
   ```bash
   ls -la /usr/local/bin/rke2
   which rke2
   ```

5. **Check logs:**
   ```bash
   sudo journalctl -u rke2-server --follow
   tail -100 /var/lib/rancher/rke2/agent/logs/kubelet.log
   ```

### Issue: RKE2 token file never appears

**Symptom:** `wait_for_rke2` provisioner times out after 120 attempts (~4 minutes)

**Solutions:**

1. **SSH to manager-1 and check RKE2 status:**
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.100
   sudo systemctl status rke2-server
   sudo systemctl start rke2-server  # if not running
   ```

2. **Wait for RKE2 to fully start:**
   ```bash
   # RKE2 may take 2-3 minutes to fully initialize
   watch -n 5 'sudo ls -la /var/lib/rancher/rke2/server/node-token 2>/dev/null || echo "Token not ready"'
   ```

3. **Check installation succeeded:**
   ```bash
   sudo journalctl -u rke2-server -n 50 | grep -E "INFO|ERROR|WARN"
   ```

4. **Verify kubeconfig exists:**
   ```bash
   sudo ls -la /etc/rancher/rke2/rke2.yaml
   ```

## Kubernetes/Rancher Issues

### Issue: RKE2 cluster is not operational

### Issue: Kubernetes cluster not coming up

**Solutions:**

1. **Check VM resources:**
   - Ensure 4 cores, 8GB RAM minimum per node
   - Check `free -h` and `nproc` in VMs

2. **Verify network:**
   - All 3 nodes must reach each other
   - Test: `ping <other-node-ip>`

3. **Check kubelet status:**
   ```bash
   # In VM:
   sudo systemctl status kubelet
   journalctl -u kubelet -n 50
   ```

4. **For Rancher installation:**
   - Install helm on Rancher manager cluster
   - Install Rancher chart: `helm repo add rancher-stable ...`
   - See Rancher documentation for full setup

## Performance Issues

### Issue: VMs deploying very slowly (> 5 minutes per VM)

**Solutions:**

1. **Check Proxmox CPU/RAM:**
   - `top` or `htop` on Proxmox host
   - Reduce parallelism if overloaded

2. **Check storage performance:**
   - `iostat -x 1` on Proxmox host
   - May indicate slow disk or ZFS issues

3. **Reduce parallelism:**
   ```bash
   terraform apply -parallelism=2
   ```

### Issue: High memory/CPU usage on Proxmox host

**Solutions:**

1. **Reduce VM resource allocation:**
   ```hcl
   variable "vm_memory_mb" {
     default = 4096  # Reduce from 8192
   }
   ```

2. **Deploy fewer VMs:**
   - Create only manager cluster first
   - Deploy apps cluster later

## Debugging Tips

### Enable Terraform Debug Logging

```bash
# For Terraform:
export TF_LOG=debug
terraform apply

# For Proxmox provider:
export PROXMOX_LOG_LEVEL=debug
terraform apply
```

### Check Terraform State

```bash
# List all resources:
terraform state list

# View specific resource:
terraform state show 'pve_qemu.vm["manager-1"]'

# Full state dump:
terraform state pull | jq .
```

### Monitor Proxmox Tasks

```bash
# Via Proxmox CLI:
pvesh get /nodes/pve1/tasks

# Via web UI:
Datacenter → Tasks → View logs
```

### Check VM Console

```bash
# Via Proxmox web UI:
VMs → Select VM → Console
# Monitor cloud-init and system startup
```

## Still Having Issues?

1. **Gather diagnostics:**
   ```bash
   terraform state list
   terraform show > state-dump.txt
   export TF_LOG=debug
   terraform plan > plan.txt 2>&1
   ```

2. **Check documentation:**
   - [TERRAFORM_GUIDE.md](TERRAFORM_GUIDE.md) - Deployment guide
   - [ARCHITECTURE.md](ARCHITECTURE.md) - System design
   - [GETTING_STARTED.md](GETTING_STARTED.md) - Setup checklist

3. **Review logs:**
   - Proxmox task history (Datacenter → Tasks)
   - VM console logs (VMs → Select VM → Console)
   - Terraform debug output (TF_LOG=debug)

## Related Documentation

- [GETTING_STARTED.md](GETTING_STARTED.md) - Quick start guide
- [TERRAFORM_GUIDE.md](TERRAFORM_GUIDE.md) - Deployment guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
