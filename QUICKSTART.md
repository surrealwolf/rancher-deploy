# Quick Start Guide

Get your Rancher clusters up and running in minutes.

## 5-Minute Setup

### 1. Prerequisites Check
```bash
make check-prereqs
```

### 2. Configure Variables
```bash
cd terraform/environments/manager
cp terraform.tfvars.example terraform.tfvars
# Edit with your Proxmox details
nano terraform.tfvars

cd ../nprd-apps
cp terraform.tfvars.example terraform.tfvars
# Edit with your Proxmox details
nano terraform.tfvars
```

### 3. Deploy Infrastructure
```bash
# From project root
make plan-manager
make apply-manager

make plan-nprd
make apply-nprd
```

Wait 10-15 minutes for VMs to initialize.

## Kubernetes Installation (Per Cluster)

### Manager Cluster

```bash
# SSH to first manager node
ssh ubuntu@192.168.1.100

# Install RKE2 server
curl -sfL https://get.rke2.io | sh -
sudo systemctl start rke2-server

# On other two nodes (as agents)
ssh ubuntu@192.168.1.101
TOKEN=$(ssh ubuntu@192.168.1.100 sudo cat /var/lib/rancher/rke2/server/token)
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent \
  INSTALL_RKE2_URL=https://192.168.1.100:6443 \
  INSTALL_RKE2_TOKEN=$TOKEN sh -
sudo systemctl start rke2-agent
```

### NPRD-Apps Cluster

Repeat the same process for 192.168.2.x nodes.

## Configure Access

```bash
./scripts/configure-kubeconfig.sh
```

This creates:
- `~/.kube/rancher-manager-config`
- `~/.kube/nprd-apps-config`

And adds shell aliases:
- `kctx-manager` - Switch to manager
- `kctx-nprd` - Switch to NPRD-Apps

## Install Rancher

```bash
kctx-manager

# Add Helm repos
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# Wait for cert-manager
kubectl wait --for=condition=available --timeout=300s \
  deployment/cert-manager -n cert-manager

# Install Rancher
helm install rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=rancher.lab.local \
  --set replicas=3 \
  --set bootstrapPassword=YourPassword \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@lab.local
```

## Access Rancher

1. Add to `/etc/hosts`:
   ```
   192.168.1.100 rancher.lab.local
   ```

2. Open: https://rancher.lab.local
3. Username: `admin`
4. Password: (from bootstrap)

## Register NPRD-Apps

1. In Rancher UI: Cluster Management → Add Cluster
2. Select "Import an existing cluster"
3. Run registration command on NPRD-Apps:
   ```bash
   kctx-nprd
   # Paste registration command
   ```

## Verify Setup

```bash
# Manager cluster
kctx-manager
kubectl get nodes
kubectl get pods -n cattle-system

# NPRD-Apps cluster
kctx-nprd
kubectl get nodes
kubectl get pods -n cattle-system
```

## Cleanup

```bash
# Destroy all
make destroy-all

# Or individual
make destroy-manager
make destroy-nprd
```

## Common Commands

```bash
# Switch contexts
kctx-manager
kctx-nprd
kctx-all

# Get cluster info
k-manager-nodes
k-nprd-nodes

# Full kubectl access
kubectl get all -A
kubectl describe node
kubectl logs deployment/rancher -n cattle-system

# Tail logs
kubectl logs -f deployment/rancher -n cattle-system
```

## Troubleshooting

### VMs not getting IPs
```bash
ssh ubuntu@192.168.1.100
sudo cloud-init status
sudo cloud-init clean --logs --seed
```

### Rancher not starting
```bash
kctx-manager
kubectl get events -n cattle-system -w
kubectl logs deployment/rancher -n cattle-system
```

### Cluster not registering
```bash
kctx-nprd
kubectl get clusterrolebinding -A | grep rancher
kubectl logs -n cattle-system -f $(kubectl get pod -n cattle-system -l app=cattle-cluster-agent -oname | head -1)
```

## Next Steps

1. ✅ Deploy infrastructure (you are here)
2. ✅ Install Kubernetes
3. ✅ Install Rancher
4. 📋 Deploy workloads to NPRD-Apps cluster
5. 📋 Configure ingress, storage, monitoring
6. 📋 Set up backup and disaster recovery

For detailed information, see:
- [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) - Complete setup guide
- [README.md](./README.md) - Architecture and overview
- [terraform/](./terraform/) - Terraform configurations
