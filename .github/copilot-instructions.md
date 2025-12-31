# Rancher on Proxmox - AI Coding Agent Instructions

## Project Overview

This is an Infrastructure-as-Code project that provisions a **two-cluster Rancher architecture on Proxmox** using Terraform:
- **rancher-manager**: 3-node management cluster (4 CPU, 8GB RAM, 100GB disk each) on `192.168.1.0/24`
- **nprd-apps**: 3-node worker cluster (8 CPU, 16GB RAM, 150GB disk each) on `192.168.2.0/24`

The manager cluster runs Rancher Server and cert-manager; the nprd-apps cluster registers to the manager. Both use RKE2 Kubernetes.

## Architecture & Data Flows

### Multi-Environment Pattern
- **Root module** (`terraform/main.tf`): Defines generic infrastructure using reusable modules
- **Environment-specific configs** (`terraform/environments/{manager,nprd-apps}/main.tf`): Call root module with environment variables
- **Key insight**: Each environment has its own `terraform.tfvars`, `backend.tf` (state isolation), and module calls with different variable values
- **Impact**: Changes to `terraform/main.tf` affect both environments; environment-specific tweaks go in `terraform/environments/*/main.tf`

### VM Provisioning Flow
1. `proxmox_vm` module clones Ubuntu 22.04 Cloud-Init template (ID specified in vars)
2. Sets static IPs via Cloud-Init (192.168.1.x for manager, 192.168.2.x for apps)
3. Provisioners run post-deployment: SSH-based setup scripts (see `scripts/install-rke2.sh`)
4. **Convention**: VM IDs follow pattern: manager=100+, nprd-apps=200+; managed via `for_each` in `terraform/main.tf` line 5-8

### Kubernetes Cluster Initialization
1. First node becomes RKE2 server: `curl -sfL https://get.rke2.io | sh -` then `systemctl start rke2-server`
2. Subsequent nodes join as agents using token from server (see `QUICKSTART.md` for manual steps)
3. `configure-kubeconfig.sh` retrieves kubeconfig from each cluster and stores in `~/.kube/`
4. **Critical**: Manager cluster kubeconfig at `192.168.1.100:/etc/rancher/rke2/rke2.yaml`; sed-patched to replace `127.0.0.1` with actual IP

## Developer Workflows

### Deployment Sequence
```bash
make check-prereqs           # Verify terraform, kubectl, helm installed
cp terraform.tfvars.example terraform.tfvars  # Both environments
# Edit with Proxmox credentials, template ID, domain
make plan-manager            # terraform init + plan (use tfplan artifact)
make apply-manager           # apply tfplan (NOT interactive apply)
# Wait 10-15 min for VMs; SSH to nodes and run: curl -sfL https://get.rke2.io | sh -
make plan-nprd && make apply-nprd  # Repeat for nprd-apps
./scripts/configure-kubeconfig.sh  # Retrieve kubeconfigs
```

### Daily Commands
- **Validate**: `make validate` (runs `terraform validate` on both envs)
- **Format**: `make fmt` (applies `terraform fmt -recursive`)
- **Destroy**: `make destroy-manager` and `make destroy-nprd` (separate targets)
- **Cleanup**: `make clean` (removes .terraform, .terraform.lock.hcl, tfplan artifacts)

### Makefile Implementation Pattern
- Variables at top: `MANAGER_ENV` and `NPRD_ENV` paths
- Cluster-specific targets prefix with environment: `plan-manager`, `apply-nprd`, `destroy-manager`
- Utility targets act on both environments (e.g., `fmt`, `validate`, `clean`)
- Uses `-out=tfplan` artifact to decouple planning and applying (best practice)

## Key Files & Patterns

### Configuration Files
- `terraform/provider.tf`: Proxmox + Helm + Kubernetes providers (all three required)
- `terraform/variables.tf`: Global variables (proxmox_api_url, ssh_private_key, etc.)
- `terraform/environments/manager/variables.tf`: Environment-specific overrides (rancher_version, rancher_hostname)
- `terraform/modules/proxmox_vm/main.tf`: Reusable VM provisioning (handles Cloud-Init, networking, cloning)

### Convention: Sensitive Variables
Mark with `sensitive = true` in variable declarations: `proxmox_token_secret`, `ssh_private_key`, `rancher_password`
- These are stored in `terraform.tfvars` (NOT version-controlled; use `.example` templates)
- Never log or output them in plan output

### Convention: Cluster Configuration Map
In `main.tf`, clusters defined as nested map with keys `manager` and `nprd-apps`:
```hcl
clusters = {
  manager = { node_count = 3, cpu_cores = 4, ip_subnet = "192.168.1.0/24", ... }
  nprd-apps = { node_count = 3, cpu_cores = 8, ip_subnet = "192.168.2.0/24", ... }
}
```
This is NOT stored as separate resource blocks—it's a map passed to modules for dynamic `for_each` loops.

### Module Usage Pattern
Both clusters use identical `proxmox_vm` module but with different specs:
```hcl
module "rancher_manager" {
  for_each = { for i in range(var.clusters["manager"].node_count) : "manager-${i+1}" => {...} }
  source = "../modules/proxmox_vm"
  # ... pass cluster["manager"] values
}
module "nprd_apps" {
  for_each = { for i in range(var.clusters["nprd-apps"].node_count) : "nprd-apps-${i+1}" => {...} }
  # ... pass cluster["nprd-apps"] values
}
```
Change cluster size/resources by editing `terraform/main.tf` cluster map, NOT individual module calls.

## Integration Points & External Dependencies

### Proxmox Integration (telmate/proxmox provider)
- **Authentication**: API token (ID + secret) via `pm_api_url`, not username/password
- **Cloning**: Requires pre-existing template VM (e.g., Ubuntu 22.04 with Cloud-Init, ID in `vm_template_id`)
- **Networking**: Assumes vmbr0 bridge exists; VMs get static IPs via Cloud-Init, not DHCP
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
