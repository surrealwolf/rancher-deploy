# Rancher Infrastructure Setup Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Proxmox Preparation](#proxmox-preparation)
5. [Deployment](#deployment)
6. [Post-Deployment](#post-deployment)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

## Overview

This Terraform configuration automates the deployment of a Rancher infrastructure on Proxmox with two Kubernetes clusters:

1. **Rancher Manager**: Central management cluster running Rancher
2. **NPRD-Apps**: Non-production applications cluster managed by Rancher

## Architecture

```
┌─────────────────────────────────────┐
│         Proxmox Host                │
├─────────────────────────────────────┤
│  Manager Cluster (3 nodes)          │
│  ├─ rancher-manager-1: 192.168.1.100
│  ├─ rancher-manager-2: 192.168.1.101
│  └─ rancher-manager-3: 192.168.1.102
│     └─ Rancher Server               │
│     └─ cert-manager                 │
│     └─ Monitoring                   │
├─────────────────────────────────────┤
│  NPRD-Apps Cluster (3 nodes)        │
│  ├─ nprd-apps-1: 192.168.2.100      │
│  ├─ nprd-apps-2: 192.168.2.101      │
│  └─ nprd-apps-3: 192.168.2.102      │
│     └─ Registered to Manager        │
└─────────────────────────────────────┘
```

## Prerequisites

### Local Machine

```bash
# Required
- Terraform >= 1.0
- curl/wget
- SSH client

# Recommended
- kubectl
- helm
- jq
```

Install Terraform:

```bash
# macOS
brew install terraform

# Ubuntu/Debian
wget https://apt.releases.hashicorp.com/gpg
sudo apt-key add gpg
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# Verify
terraform version
```

### Proxmox

- Proxmox VE 6.4+ installed and configured
- Network connectivity to API endpoint
- API token with necessary permissions
- Ubuntu 22.04 LTS Cloud-Init template

## Proxmox Preparation

### 1. Create API Token

1. Log into Proxmox Web UI
2. Navigate to: Datacenter → Users → Select your user → API Tokens
3. Click "Add"
4. Token ID: `terraform`
5. Check "Privilege Separation" (optional)
6. Click "Add"
7. Save the token value

### 2. Create Ubuntu Template

Download Ubuntu Cloud Image:

```bash
# SSH into Proxmox node
ssh root@proxmox.local

# Create Ubuntu template
qm create 100 \
  --name ubuntu-22.04 \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0

# Download image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
qm importdisk 100 jammy-server-cloudimg-amd64.img local-lvm

# Configure disk
qm set 100 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-100-disk-0

# Configure Cloud-Init
qm set 100 --ide2 local-lvm:cloudinit
qm set 100 --boot c --bootdisk scsi0
qm set 100 --serial0 socket

# Convert to template
qm template 100

rm jammy-server-cloudimg-amd64.img
```

### 3. Verify Network Configuration

```bash
# Verify bridges exist
ip link show | grep vmbr

# If needed, create additional bridge:
# Edit /etc/network/interfaces
```

## Deployment

### Step 1: Clone Repository

```bash
cd ~/git
git clone <your-repo-url> rancher
cd rancher
```

### Step 2: Configure Variables

#### Manager Environment

```bash
cd terraform/environments/manager
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Proxmox Configuration
proxmox_api_url      = "https://192.168.1.10:8006/api2/json"
proxmox_token_id     = "terraform@pam!terraform"
proxmox_token_secret = "your-api-token-value-here"
proxmox_tls_insecure = true
proxmox_node         = "pve-01"

# VM Configuration
vm_template_id       = 100
ssh_private_key      = "~/.ssh/id_rsa"

# Rancher Configuration
rancher_hostname = "rancher.lab.local"
rancher_password = "YourSecurePassword123!"
rancher_version  = "v2.7.7"

# Network Configuration
domain      = "lab.local"
dns_servers = ["8.8.8.8", "8.8.4.4"]
storage     = "local-lvm"
```

#### NPRD-Apps Environment

```bash
cd ../nprd-apps
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Use same Proxmox credentials as manager
proxmox_api_url      = "https://192.168.1.10:8006/api2/json"
proxmox_token_id     = "terraform@pam!terraform"
proxmox_token_secret = "your-api-token-value-here"
proxmox_tls_insecure = true
proxmox_node         = "pve-01"

# VM Configuration
vm_template_id  = 100
ssh_private_key = "~/.ssh/id_rsa"

# Cluster Configuration
node_count   = 3
cpu_cores    = 8
memory_mb    = 16384
disk_size_gb = 150

# Network Configuration
gateway     = "192.168.1.1"
dns_servers = ["8.8.8.8", "8.8.4.4"]
storage     = "local-lvm"
```

### Step 3: Validate Configuration

```bash
# From project root
make validate
```

### Step 4: Deploy Manager Cluster

```bash
make plan-manager
make apply-manager
```

Wait for VMs to be created and initialized (5-10 minutes).

### Step 5: Install Kubernetes on Manager

```bash
# SSH into first manager node
ssh ubuntu@192.168.1.100

# Download and run RKE2 installation
curl -sfL https://get.rke2.io | sh -
sudo systemctl start rke2-server
sudo systemctl enable rke2-server

# Wait for cluster to be ready
sudo /opt/rke2/bin/kubectl get nodes

# Repeat for other manager nodes (as agents)
ssh ubuntu@192.168.1.101
# Get token from first node
TOKEN=$(sudo cat /var/lib/rancher/rke2/server/token)
SERVER_URL="https://192.168.1.100:6443"

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent sh -
# Configure and start agent
```

### Step 6: Deploy NPRD-Apps Cluster

```bash
make plan-nprd
make apply-nprd
```

Install Kubernetes on NPRD-Apps nodes similarly to manager cluster.

## Post-Deployment

### 1. Configure Kubeconfig

```bash
chmod +x scripts/configure-kubeconfig.sh
./scripts/configure-kubeconfig.sh
```

This will:
- Retrieve kubeconfig from both clusters
- Update server IPs
- Create context switching aliases

### 2. Verify Cluster Connectivity

```bash
# Manager cluster
export KUBECONFIG=~/.kube/rancher-manager-config
kubectl get nodes

# NPRD-Apps cluster
export KUBECONFIG=~/.kube/nprd-apps-config
kubectl get nodes
```

### 3. Install Rancher on Manager

```bash
export KUBECONFIG=~/.kube/rancher-manager-config

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=300s

# Install Rancher
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
helm install rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=rancher.lab.local \
  --set replicas=3 \
  --set bootstrapPassword=YourSecurePassword123! \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=rancher@lab.local

# Wait for Rancher to be ready
kubectl rollout status deployment/rancher -n cattle-system
```

### 4. Access Rancher UI

1. Add DNS entry or edit /etc/hosts:
   ```
   192.168.1.100 rancher.lab.local
   ```

2. Open browser: https://rancher.lab.local
3. Login with username: `admin`
4. Password: (from terraform.tfvars)

### 5. Register NPRD-Apps Cluster

1. In Rancher UI: Cluster Management → Add Cluster
2. Select "Import an existing cluster"
3. Copy the provided registration command
4. Run on NPRD-Apps cluster:
   ```bash
   export KUBECONFIG=~/.kube/nprd-apps-config
   # Paste the registration command
   ```

## Verification

### Manager Cluster Health

```bash
export KUBECONFIG=~/.kube/rancher-manager-config

# Check nodes
kubectl get nodes

# Check Rancher pods
kubectl get pods -n cattle-system

# Check cert-manager
kubectl get pods -n cert-manager

# Check cluster health
kubectl cluster-info
```

### NPRD-Apps Cluster Health

```bash
export KUBECONFIG=~/.kube/nprd-apps-config

# Check nodes
kubectl get nodes

# Check registration
kubectl get pods -n cattle-system

# Verify manager connection
kubectl logs -n cattle-system -l app=cattle-cluster-agent -f
```

### Network Connectivity

```bash
# Test DNS from manager node
ssh ubuntu@192.168.1.100
nslookup rancher.lab.local

# Test DNS from nprd-apps node
ssh ubuntu@192.168.2.100
nslookup rancher.lab.local
```

## Troubleshooting

### VMs Not Getting IP

**Problem**: VMs show no IP address

**Solution**:
```bash
# Check cloud-init logs on VM
ssh ubuntu@192.168.1.100
sudo tail -50 /var/log/cloud-init-output.log

# Manually configure network
sudo netplan apply
```

### Rancher Pod Not Starting

**Problem**: Rancher pods stuck in pending or crash loop

**Solution**:
```bash
# Check logs
kubectl logs -n cattle-system deployment/rancher

# Check persistent volumes
kubectl get pvc -n cattle-system

# Check node resources
kubectl top nodes
kubectl top pods -n cattle-system
```

### NPRD-Apps Not Registering

**Problem**: Cluster doesn't show in Rancher UI

**Solution**:
```bash
# Check agent logs on NPRD-Apps
export KUBECONFIG=~/.kube/nprd-apps-config
kubectl logs -n cattle-system -l app=cattle-cluster-agent -f

# Verify connectivity from NPRD to Manager
curl -k https://192.168.1.100:6443

# Re-run registration command
```

### SSL Certificate Issues

**Problem**: HTTPS connection errors

**Solution**:
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificates
kubectl get certificate -A

# Force renewal
kubectl delete secret rancher-tls -n cattle-system
kubectl delete certificate rancher -n cattle-system
```

## Cleanup

### Destroy NPRD-Apps Cluster

```bash
make destroy-nprd
```

### Destroy Manager Cluster

```bash
make destroy-manager
```

### Destroy Everything

```bash
make destroy-all
```

## Advanced Configuration

### Custom DNS

Edit `terraform/environments/*/terraform.tfvars`:

```hcl
dns_servers = ["1.1.1.1", "1.0.0.1"]  # Cloudflare DNS
```

### Different VM Specs

Edit `terraform/environments/*/terraform.tfvars`:

```hcl
# For manager
cpu_cores    = 8     # Increase from 4
memory_mb    = 16384 # Increase from 8192
disk_size_gb = 150   # Increase from 100

# For NPRD-Apps
node_count   = 5     # Increase from 3
```

### High Availability Setup

For production, consider:
- Load balancer for Rancher (not included)
- Persistent storage for databases
- Backup strategy for Rancher state
- Network segmentation between clusters

## Support and References

- [Rancher Documentation](https://rancher.com/docs/)
- [Telmate Proxmox Provider](https://github.com/Telmate/proxmox-terraformer)
- [RKE2 Documentation](https://docs.rke2.io/)
- [Terraform Documentation](https://www.terraform.io/docs/)
