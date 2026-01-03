# Copilot Instructions for Rancher Deploy Project

## Project Overview

This project deploys a complete Rancher management cluster and non-production apps cluster on Proxmox using Terraform. It demonstrates infrastructure-as-code best practices with automated VM provisioning, networking, and cluster orchestration.

- **Rancher Manager Cluster**: 3 nodes (VM 401-403), runs Rancher control plane
- **NPRD Apps Cluster**: 3 nodes (VM 404-406), non-production workloads
- **Network**: Unified VLAN 14 (192.168.1.x/24) for simplified management
- **Provider**: bpg/proxmox v0.90.0 (reliable, well-maintained)
- **Kubernetes**: RKE2 v1.34.3+rke2r1 (specific stable version - NOT "latest")

## Latest Updates (Jan 1, 2026)

### Critical Fix: RKE2 Version
- **Issue**: RKE2 "latest" is not a downloadable release
- **Solution**: Use specific version tags like `v1.34.3+rke2r1`
- **Check**: https://github.com/rancher/rke2/tags for available versions
- **Prevention**: Always validate version exists before deployment

### Cloud-Init Integration
- Added `wait_for_cloud_init` provisioner to ensure networking is ready before RKE2 installation
- Waits for `/var/lib/cloud/instance/boot-finished` and `cloud-init status --wait`
- Prevents RKE2 installation on systems with incomplete networking

### RKE2 Installation Improvements
- Changed from piped curl to download + execute pattern for better error handling
- Fixed environment variable passing with `sudo -E bash -c` pattern
- Added cleanup of SSH known_hosts to prevent host key warnings
- Added explicit SSH connectivity checks before RKE2 operations
- Added token file polling with 120 attempts over 4 minutes

### Logging Support
- Added `apply.sh` script in root directory with automatic logging
- Logs saved to timestamped files: `terraform/terraform-<timestamp>.log`
- Debug logging enabled via `TF_LOG=debug` environment variable
- Log levels: trace, debug, info, warn, error
- See [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) for logging details

### RKE2 Provisioning Lessons Learned (Jan 2, 2026)

**Critical Discovery: Network Readiness Timing**
- VMs must wait for **complete cloud-init initialization** before attempting RKE2 installation
- Initial provisioner approach with minimal sleep (10s) was **insufficient** and caused hanging
- Remote-exec provisioners trigger SSH connection checks but don't guarantee system readiness

**Solutions Implemented:**
1. **cloud-init Status Check**: Script now runs `cloud-init status --wait` with timeout
2. **Network Connectivity Verification**: Ping test to 8.8.8.8 before attempting downloads
3. **DNS Resolution Validation**: nslookup test for get.rke2.io before curl download
4. **Exponential Retry Logic**: Multiple retries with logged attempts (30-120 attempts per check)
5. **curl Timeout Protection**: Added `--max-time 60 --connect-timeout 30` to curl command with `timeout 60` wrapper

### SSH Timeout Root Cause - Intrusion Prevention System (Jan 2, 2026)

**Discovery**: Intermittent SSH timeouts during provisioning caused by **Intrusion Prevention System (IPS) blocking high-frequency SSH connections**

**Symptoms**:
- SSH initial connection works (script uploads successfully)
- SSH reconnect hangs for 5+ minutes during provisioning
- Affects multiple nodes inconsistently
- Eventually times out or connects after IPS timeout resets

**Root Cause**: IPS systems treat repeated SSH connections from automation tools as potential attack pattern during heavy provisioning activity

**Prevention for Future Deployments**:
1. Whitelist Terraform runner IP in IPS/firewall rules
2. Configure IPS to allow high-frequency SSH from known automation IPs
3. Disable/bypass IPS for test environments during deployment
4. Contact network team to increase SSH connection thresholds

**Impact**: Does NOT affect curl timeout fix or provisioning script logic - it's a network-level security issue separate from RKE2 installation

**Updated Script Location:** `terraform/modules/proxmox_vm/cloud-init-rke2.sh`

**Deployment Sequence with Proper Waiting:**
```
1. VM created and boots (30-50 seconds)
2. SSH provisioner connects (attempts until available)
3. RKE2 installation script begins
4. Script waits for cloud-init completion (120 seconds max)
5. Script verifies network connectivity (30 seconds max)
6. Script verifies DNS resolution (30 seconds max)
7. RKE2 installer downloaded and executed (5-10 minutes)
8. Token file polling for cluster readiness (120 seconds max)
```

**Key Takeaway for Future Development:**
- Never assume SSH connectivity implies system readiness
- Always verify cloud-init completion explicitly
- Always test network connectivity before external downloads
- Use logging (tee -a) to track all provisioning steps
- Provide clear retry messages for debugging

### RKE2 Installer Download Fix - Write Error (Jan 2, 2026)

**Critical Discovery**: RKE2 installer download failing with curl exit code 23 (write error)

**Root Cause**: The cloud-init wrapper script copies itself to `/tmp/rke2-install.sh`, then tries to download the actual RKE2 installer to the same filename. When the script is running from that path, **the OS prevents overwriting the currently-executing file**, causing curl write errors.

**Symptoms**:
- Download appears to fail silently (all 5 retries fail identically)
- Direct curl testing from VM succeeds, but fails within the script
- HTTP response 200 (success) but curl exits with code 23 (write error)
- All 3 managers fail at same step with identical error pattern

**Solution Implemented**:
Changed installer download path from `/tmp/rke2-install.sh` to `/tmp/rke2-installer.sh`:
- Script wrapper stays at `/tmp/rke2-install.sh`
- Actual RKE2 installer downloads to `/tmp/rke2-installer.sh`
- No conflict between executing wrapper and downloaded binary
- Both execution paths (`"$INSTALLER"` lines) use correct variable

**Error Detection**:
Added error capture to script to expose curl exit codes:
```bash
CURL_OUTPUT=$(timeout 60 curl -sfL ... 2>&1)
CURL_EXIT=$?
if [ $CURL_EXIT -ne 0 ]; then
  log "  curl exit code: $CURL_EXIT, error: $CURL_OUTPUT"
fi
```

**Curl Exit Codes Reference**:
- Exit code 0: Success
- Exit code 23: Write/read error (prevented from writing to executing file)
- Exit code 28: Operation timeout
- Exit code 35: SSL/TLS error

**Files Changed**:
- `terraform/modules/proxmox_vm/cloud-init-rke2.sh`: Line 37 (INSTALLER path changed)
- Enhanced error logging for curl operations (lines 40-56)

**Testing Verification**:
✅ Tested on live VM:
```
Download attempt 1/5...
✓ RKE2 installer downloaded successfully
Installing RKE2 server v1.34.3+rke2r1...
```

**Key Takeaway**:
- Always use different filenames for downloaded content vs executing wrapper
- Expose curl errors (don't suppress with 2>/dev/null) during debugging
- Test actual provisioner environment (with sudo -E) not just direct curl

### RKE2 Provisioning Timeout Fix - Non-Blocking Installation (Jan 2, 2026)

**Issue**: Provisioner script was timing out waiting for RKE2 services to become fully operational before exiting

**Root Cause**: The script contained blocking waits (60 attempts, ~120 seconds each) for:
1. RKE2 service to become active
2. Token file to be created

These waits could exceed the provisioner connection timeout, causing `remote-exec` provisioner to fail even though RKE2 was installing in the background.

**Solution Implemented**:
Changed from blocking to non-blocking approach:
1. **Removed service startup waits**: Script now exits successfully after running installer
2. **Increased provisioner timeout**: From `10m` to `30m` in terraform config
3. **Added helpful messages**: Notes that services will start automatically

**Before (Blocking)**:
```bash
log "Waiting for RKE2 server to start..."
for i in {1..60}; do
  if systemctl is-active --quiet rke2-server; then
    log "✓ RKE2 server is running"
    break
  fi
  sleep 2
done

if [ ! -f /var/lib/rancher/rke2/server/node-token ]; then
  log "✗ Token file not found"
  exit 1
fi
```

**After (Non-Blocking)**:
```bash
log "RKE2 installation complete. Service will start automatically."
log "ⓘ Note: RKE2 service may take several minutes to fully initialize"
```

**Benefits**:
- ✅ Provisioner completes successfully and returns control faster
- ✅ RKE2 services start automatically in background
- ✅ Terraform state is saved even if service startup is slow
- ✅ Users can manually check status: `systemctl status rke2-server`
- ✅ No more false provisioner failures

**Terraform Change**:
```hcl
# terraform/modules/proxmox_vm/main.tf
connection {
  timeout = "30m"  # Increased from "10m"
}
```

**Deployment Pattern**:
```
1. VM boots (30-50 seconds)
2. SSH provisioner connects
3. RKE2 installer runs and completes (~3-5 minutes)
4. Script exits successfully ✓
5. Terraform marks VM as complete
6. RKE2 services start in background (continues for 2-3 minutes)
7. Services become available without blocking provisioner
```

**Post-Deployment Verification**:
```bash
# Check service status (may take 2-3 minutes after provisioner completes)
systemctl status rke2-server

# Check if token file exists
ls -la /var/lib/rancher/rke2/server/node-token

# Verify kubernetes
KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl get nodes
```

**Key Takeaway**:
- Provisioners should complete quickly and exit successfully
- Long-running background services (like RKE2) should start independently
- Don't block provisioners waiting for service startup
- Use post-deployment checks instead of blocking waits

## Project Structure

### Documentation (`docs/`)
Core documentation for users and developers:
- `DEPLOYMENT_GUIDE.md` - Complete deployment guide with logging instructions
- `TERRAFORM_VARIABLES.md` - Detailed variable reference
- `TROUBLESHOOTING.md` - Common issues and solutions (includes RKE2 version fix)
- `CLOUD_IMAGE_SETUP.md` - Cloud image provisioning details
- `TFVARS_SETUP.md` - Setup and configuration instructions
- `RANCHER_DEPLOYMENT.md` - Rancher deployment automation

### Terraform Configuration (`terraform/`)
Infrastructure-as-code using Terraform:
- `main.tf` - Cluster module definitions (uses v1.34.3+rke2r1)
- `provider.tf` - bpg/proxmox provider configuration with logging comments
- `variables.tf` - Input variable definitions and defaults
- `outputs.tf` - Output values for cluster access
- `terraform.tfvars.example` - Example variable values (copy and customize)
- `modules/proxmox_vm/` - Reusable VM resource module
- `modules/rke2_cluster/` - RKE2 installation with provisioners

### Scripts (Root)
- `apply.sh` - Deploy with automatic logging (recommended method)

## Key Guidelines

### Terraform Development

#### Variable Naming and Documentation
- Use snake_case for variable names
- Always include `description` field explaining purpose
- Use `type` to enforce data types (string, number, map, list, etc.)
- Mark sensitive values with `sensitive = true`
- Provide realistic defaults where appropriate

**Sensitive Variables:**
- `proxmox_api_token_secret`
- `ssh_private_key`
- Store in `terraform.tfvars` (never commit actual values)
- Use `terraform.tfvars.example` as template for users

#### Module Architecture
- **Single module pattern**: `proxmox_vm` module handles all VM creation
- **Cluster orchestration**: Pass cluster configuration via variables, not hard-coded values
- **Module reusability**: Both manager and apps clusters use same module with different parameters
- **Explicit dependencies**: Use `depends_on` to control deployment order (apps waits for manager)

#### Resource Naming
- **Provider resources**: `proxmox_virtual_environment_vm` (from bpg/proxmox)
- **Terraform variables**: snake_case (e.g., `proxmox_api_url`)
- **Terraform outputs**: snake_case (e.g., `rancher_manager_ip`)
- **Local values**: snake_case (e.g., `vm_tags`)

#### Network Configuration
- **VLAN**: 14 (unified segment)
- **Manager nodes**: 192.168.1.10x (100-102)
- **Apps nodes**: 192.168.1.11x (110-112)
- **Gateway**: 192.168.1.1
- **Cloud-init**: Handles static IP, DNS, hostname configuration

#### Cluster Orchestration Pattern
```hcl
module "rancher_manager" {
  source = "./modules/proxmox_vm"
  # ... configuration for 3-node manager cluster
}

module "nprd_apps" {
  source = "./modules/proxmox_vm"
  depends_on = [module.rancher_manager]  # Manager first
  # ... configuration for 3-node apps cluster
}
```

### Documentation Standards

#### README.md Structure
1. Project title and purpose
2. Features list
3. Architecture overview (brief)
4. Prerequisites section
5. Quick start (3-5 steps)
6. Documentation links (point to docs/ folder)
7. Project structure overview
8. Key features explanation
9. Usage and configuration
10. Troubleshooting basics with link to detailed guide
11. Support and resources

#### Guide Documents (in `docs/`)
Follow consistent structure:
1. **Title**: Clear indication of guide purpose
2. **Overview**: What will be accomplished
3. **Prerequisites**: Required tools, accounts, knowledge
4. **Step-by-step instructions**: Numbered, clear, testable
5. **Configuration examples**: Real code with explanations
6. **Verification**: How to confirm success
7. **Troubleshooting**: Issues specific to this guide
8. **Next steps**: Related guides or post-deployment tasks
9. **Related documentation**: Cross-references to other docs

#### Troubleshooting Guide Format
Organize by category (Terraform, Proxmox API, VMs, Networking, SSH, etc.):
```markdown
## Category Name

### Issue: [User-facing symptom]
**Error message**: [Actual error text if applicable]
**Solutions**:
1. [First approach with commands]
2. [Alternative approach]
3. [Debug/diagnostic approach]
```

#### Architecture Documentation
Include:
- System diagram/ASCII art
- Component descriptions
- Network topology
- Data flows
- Resource requirements
- Scalability considerations
- Disaster recovery approach

### Provider Information

#### Current: bpg/proxmox v0.90.0
**Advantages over other providers:**
- ✅ Reliable task polling with exponential backoff retry
- ✅ Better error handling and diagnostics
- ✅ Proper cloud-init integration
- ✅ Full Proxmox VE 8.x and 9.x support
- ✅ Improved API stability
- ✅ Active community development (1.7K+ GitHub stars, 130+ contributors)

**Resource Type**: `proxmox_virtual_environment_vm` for QEMU VMs

**Provider Configuration:**
```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_user}!${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure
  
  ssh {
    agent    = true
    username = "root"
  }
}
```

### Best Practices

#### Infrastructure as Code Principles
1. **Idempotency**: Apply multiple times with same result
2. **State isolation**: Separate tfvars for different environments
3. **Modularity**: Reuse modules, avoid code duplication
4. **Documentation**: Every variable must be documented
5. **Version pinning**: Use specific versions (RKE2), not "latest"
5. **Version control**: Git for all code and examples

#### Cluster Deployment
1. **Sequence**: Manager cluster always first
2. **Dependencies**: Use `depends_on` for explicit ordering
3. **Configuration**: Cloud-init handles all post-boot setup
4. **Verification**: SSH access verifies successful deployment
5. **Timing**: Allow 2-3 minutes total for all 6 VMs

#### Network Configuration
- **VLAN tagging**: Applied at vmbr0 level in Proxmox
- **Static IPs**: Configured via cloud-init, not DHCP
- **Connectivity**: Test with ping before proceeding
- **DNS**: Configured per cluster, can be customized
- **Unified segment**: All VMs on same VLAN for simplicity

#### Debugging Techniques
```bash
# Terraform debugging
export TF_LOG=debug
terraform plan > debug.log 2>&1

# Provider debugging
export PROXMOX_LOG_LEVEL=debug
terraform apply

# Check Proxmox tasks
# Via UI: Datacenter → Tasks → View logs

# Monitor VM console
# Via UI: VMs → Select VM → Console → Monitor cloud-init

# Verify in VM
ssh ubuntu@192.168.1.100
cloud-init status
cloud-init query
ip addr show
```

### Code Quality Standards

#### Terraform Formatting
```bash
# Format all Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Check for unused variables
terraform console  # Then: keys(var.*)
```

#### Documentation Quality
- Clear, concise language (avoid jargon where possible)
- Code examples for all configuration options
- Cross-references between related topics
- Troubleshooting sections in major guides
- Consistent formatting and styling

#### Error Handling
- Meaningful error messages
- Provide solutions, not just problems
- Include command examples for debugging
- Link to relevant troubleshooting sections

## Common Development Tasks

### Adding a New Documentation File

1. **Create file in `docs/`**: Use descriptive name (e.g., `DEPLOYMENT_GUIDE.md`)
2. **Structure content**:
   - Header with clear title
   - Overview paragraph
   - Prerequisites section
   - Main content with examples
   - Troubleshooting for that topic
   - Links to related docs
3. **Cross-reference**:
   - Add link to README.md documentation section
   - Link from related documents
   - Include in .github/copilot-instructions.md

### Updating Terraform Configuration

1. **Format code**: `terraform fmt -recursive`
2. **Validate**: `terraform validate`
3. **Review**: Check variable descriptions are clear
4. **Test plan**: `terraform plan > plan.txt` (review changes)
5. **Manual test** (if applicable):
   - Plan on test environment
   - Apply changes
   - Verify VMs are created and configured
   - Destroy to clean up
6. **Commit**: Clear message describing changes

### Handling Issues and Troubleshooting

1. **Reproduce**: Run with debug logging enabled
   ```bash
   export TF_LOG=debug TF_LOG_PATH=terraform.log
   terraform apply -auto-approve
   ```

2. **Gather info**:
   - Terraform state: `terraform state list`
   - Terraform logs: Check `terraform/terraform-*.log`
   - Proxmox task history
   - VM console output
   - Cloud-init logs in VM

3. **Document solution**: Add to TROUBLESHOOTING.md if applicable
4. **Test fix**: Verify in test environment
5. **Commit**: Reference issue if applicable

### RKE2 Version Management

1. **Check available versions**: https://github.com/rancher/rke2/tags
2. **Always use specific versions**: `v1.34.3+rke2r1` NOT "latest"
3. **Update in two places**:
   - `terraform/main.tf` - Module calls for both clusters
   - `terraform/modules/rke2_cluster/main.tf` - Module default
4. **Clean state after version change**:
   ```bash
   rm -f terraform.tfstate*
   terraform apply -auto-approve
   ```

### Deploying with Logging

**RECOMMENDED: Use the apply.sh script**

```bash
# From project root directory
./apply.sh -auto-approve
```

This automatically:
- Sets up debug logging (`TF_LOG=debug`)
- Saves logs to timestamped file: `terraform/terraform-<timestamp>.log`
- Changes to terraform directory
- Runs terraform apply with auto-approval
- Monitors progress in background

**Manual deployment with logging:**

```bash
cd terraform
export TF_LOG=debug TF_LOG_PATH=terraform.log
terraform apply -auto-approve
```

**Log levels (TF_LOG environment variable):**
- `trace` - Most verbose (includes all API calls)
- `debug` - Detailed operation info (recommended)
- `info` - Normal output (least verbose)
- `warn` / `error` - Only warnings and errors

**Deployment timeline expectations:**
1. **Cloud image download**: 30-40 seconds (3 images in parallel)
2. **VM creation**: 1-2 minutes (provisioners start immediately)
3. **SSH connection attempts**: 3-5 minutes (VMs booting, SSH becoming available)
4. **RKE2 installation**: 5-10 minutes per cluster (parallel across nodes)
5. **Token verification**: 1-2 minutes (rke2_cluster module polling)
6. **Total deployment time**: 15-25 minutes from terraform apply start

**Monitoring deployment progress:**

```bash
# From another terminal, tail the log file
tail -f terraform/terraform-<timestamp>.log

# Filter for key events
grep -E "Creating|Complete|ERROR" terraform/terraform-<timestamp>.log

# Watch SSH connection attempts
grep "Connecting to remote host via SSH" terraform/terraform-<timestamp>.log
```

## Testing Recommendations

### Before Pushing Changes

1. **Syntax and formatting**:
   ```bash
   terraform fmt -recursive
   terraform validate
   ```

2. **Documentation review**:
   - Check all examples are correct
   - Verify cross-references work
   - Test commands shown in docs

3. **Code review**:
   - Variables are documented
   - No hardcoded values
   - Proper error handling

4. **Manual testing** (in test environment):
   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   # Verify outputs and VM access
   terraform destroy
   ```

### Full Integration Test Procedure

```bash
# 1. Clean state
cd /path/to/rancher-deploy/terraform
rm -rf .terraform .terraform.lock.hcl
rm -f tfplan

# 2. Fresh init and plan
terraform init
terraform plan -out=tfplan
# Review plan carefully

# 3. Apply and verify
terraform apply tfplan
terraform output
# Check IPs and test SSH access

# 4. Cleanup
terraform destroy
```

## Quick Reference

### Essential Files
| File | Purpose |
|------|---------|
| `README.md` | Project overview and quick-start |
| `terraform/main.tf` | Cluster definitions |
| `terraform/provider.tf` | Provider configuration |
| `docs/GETTING_STARTED.md` | User setup guide |
| `docs/TERRAFORM_GUIDE.md` | Detailed deployment |
| `docs/TROUBLESHOOTING.md` | Issue resolution |

### Important Commands
```bash
# Terraform core
terraform init              # Initialize Terraform
terraform validate          # Validate configuration
terraform fmt -recursive    # Format code
terraform plan             # Preview changes
terraform apply            # Apply changes
terraform destroy          # Remove infrastructure

# Debugging
export TF_LOG=debug        # Enable Terraform debug
export PROXMOX_LOG_LEVEL=debug  # Enable provider debug

# State inspection
terraform state list       # List resources
terraform state show <resource>  # Show resource details
```

### Useful Variables
- `proxmox_api_url`: Proxmox API endpoint
- `proxmox_api_user`: API user (e.g., terraform@pam)
- `proxmox_api_token_id`: Token ID from API token
- `proxmox_api_token_secret`: Token secret (sensitive)
- `vm_template_id`: Ubuntu template VM ID (default: 400)
- `ssh_private_key`: Path to SSH key for VM access

## Documentation Maps

### For Users
1. Start: [README.md](../README.md)
2. Setup: [GETTING_STARTED.md](../docs/GETTING_STARTED.md)
3. Deploy: [TERRAFORM_GUIDE.md](../docs/TERRAFORM_GUIDE.md)
4. Understand: [ARCHITECTURE.md](../docs/ARCHITECTURE.md)
5. Troubleshoot: [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)

### For Developers
1. Review: [ARCHITECTURE.md](../docs/ARCHITECTURE.md)
2. Setup: [GETTING_STARTED.md](../docs/GETTING_STARTED.md)
3. Modify: [TERRAFORM_GUIDE.md](../docs/TERRAFORM_GUIDE.md)
4. Debug: [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
5. Reference: This file (.github/copilot-instructions.md)

## Support and Resources

### External Documentation
- **Proxmox**: https://pve.proxmox.com/wiki/Main_Page
- **Terraform**: https://www.terraform.io/docs/
- **Rancher**: https://rancher.com/docs/
- **Provider**: https://github.com/surrealwolf/terraform-pve

### Internal Documentation
- Project README: [../README.md](../README.md)
- Getting Started: [../docs/GETTING_STARTED.md](../docs/GETTING_STARTED.md)
- All guides: [../docs/](../docs/)
- **Gotchas**: TLS validation can be disabled via `proxmox_tls_insecure` (for lab/dev only)

### RKE2 Kubernetes
- **Installation**: Manual per-node via `curl ... | sh -` (NOT automated by Terraform; docs assume SSH post-deploy)
- **First node**: Becomes RKE2 server; generates token for agent joins
- **Token sharing**: Agents need server token—documented in `QUICKSTART.md`, must be retrieved manually from server node
- **Kubeconfig**: Retrieved post-deployment via `configure-kubeconfig.sh` which SCPs from `/etc/rancher/rke2/rke2.yaml`

### Rancher + cert-manager
- Not yet provisioned by Terraform (Helm providers defined but unused in current implementation)
- **TODO**: `terraform/modules/rancher_cluster/main.tf` exists but is not called; should deploy Rancher Server on manager via Helm

## Testing & Validation

### Pre-Deployment Checks
- `terraform validate`: Checks syntax (run via `make validate-manager` and `make validate-nprd`)
- `terraform plan -out=tfplan`: Shows changes; artifact is committed for `apply` (not re-planned interactively)

### Post-Deployment Verification
1. VMs exist in Proxmox UI with correct IPs and hostnames
2. SSH to each node: `ssh ubuntu@192.168.1.100` (and .101, .102, then 192.168.2.x nodes)
3. After RKE2 install: `kubectl get nodes` from kubeconfig should list 3 nodes per cluster
4. Rancher manager accessible at `https://rancher_hostname` (bootstrapped with `rancher_password`)

## Common Mistakes to Avoid

1. **Mixing environments**: Don't run `terraform apply` from root; always CD into `terraform/environments/{manager,nprd-apps}`
2. **State pollution**: Each environment has separate `backend.tf` and S3/local state; destroying one doesn't affect the other
3. **Forgotten `.tfvars`**: Copy `.example` and edit BEFORE `terraform init`; missing variables will error at init time
4. **Template ID mismatch**: Proxmox template ID must exist and have Cloud-Init; verify in Proxmox UI before deploy
5. **SSH key permissions**: `ssh_private_key` path in vars must be readable; use absolute paths
6. **IP conflicts**: Manager and nprd-apps use separate subnets (192.168.1.x vs 192.168.2.x) to avoid overlap; if modifying, ensure no collisions
