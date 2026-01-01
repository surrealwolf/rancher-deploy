# Rancher Deployment via Terraform

This project now automates the complete Rancher deployment using Terraform, from VM provisioning through Rancher installation.

## Deployment Pipeline

```
1. Provision VMs (bpg/proxmox provider)
   ↓
2. Install RKE2 Kubernetes (rke2_cluster module)
   ├── Initialize server nodes
   ├── Join additional server nodes
   └── Retrieve kubeconfig
   ↓
3. Deploy Rancher (rancher_cluster module)
   ├── Install cert-manager
   ├── Install Rancher Helm chart
   └── Configure bootstrap password
```

## What's Automated

### Infrastructure (Terraform)
- ✅ VM provisioning with cloud images
- ✅ Network configuration (IP, DNS, gateway)
- ✅ VLAN configuration

### Kubernetes (RKE2)
- ✅ RKE2 installation on all nodes
- ✅ Server node clustering
- ✅ kubeconfig retrieval and local storage
- ✅ Automatic node joining

### Rancher
- ✅ cert-manager installation
- ✅ Rancher Helm deployment
- ✅ Bootstrap password configuration
- ✅ Ingress configuration

## Required Variables

Add these to `terraform.tfvars`:

```hcl
# Kubernetes/Rancher
rancher_version  = "v2.7.7"
rancher_password = "your-secure-bootstrap-password"
rancher_hostname = "rancher.example.com"

# Existing variables (proxmox, clusters, etc.)
```

## Deployment Steps

### 1. Prepare Configuration

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox and Rancher settings
```

### 2. Preview Deployment

```bash
terraform plan
```

This will show:
- 6 VMs to be created
- RKE2 installation tasks
- Rancher deployment tasks

### 3. Deploy

```bash
terraform apply
```

**Estimated time:** 30-45 minutes total
- VM provisioning: 10-15 minutes
- RKE2 installation: 15-20 minutes
- Rancher deployment: 5-10 minutes

### 4. Verify Deployment

```bash
# Check manager cluster
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get nodes
kubectl get pods -n cattle-system

# Check apps cluster
export KUBECONFIG=~/.kube/nprd-apps.yaml
kubectl get nodes
kubectl get pods -n cattle-system
```

## Accessing Rancher

1. **Get the Rancher password:**
   - Defined in `terraform.tfvars` as `rancher_password`
   - Use username: `admin`

2. **Configure DNS:**
   - Point `rancher.example.com` to one of the manager cluster IPs
   - Or use port forwarding: `kubectl port-forward -n cattle-system svc/rancher 443:443`

3. **Access Rancher:**
   ```
   https://rancher.example.com
   Username: admin
   Password: <from rancher_password>
   ```

## Modules

### rke2_cluster
Installs RKE2 Kubernetes on VMs via SSH provisioners.

**Inputs:**
- `cluster_name` - Cluster name
- `server_ips` - List of server node IPs
- `agent_ips` - List of agent node IPs (optional)
- `ssh_private_key_path` - Path to SSH key
- `ssh_user` - SSH user (default: ubuntu)
- `rke2_version` - RKE2 version (default: latest)

**Outputs:**
- `kubeconfig_path` - Path to kubeconfig file
- `api_server_url` - Kubernetes API server URL
- `cluster_name` - Cluster name

### rancher_cluster
Deploys Rancher and cert-manager via Helm.

**Inputs:**
- `cluster_name` - Cluster name
- `kubeconfig_path` - Path to kubeconfig
- `install_rancher` - Whether to install Rancher
- `rancher_version` - Rancher version
- `rancher_password` - Bootstrap password
- `rancher_hostname` - Rancher FQDN

**Outputs:**
- `kubeconfig_path` - Kubeconfig path
- `cluster_name` - Cluster name

## Troubleshooting

### RKE2 Installation Fails

**Check logs:**
```bash
ssh ubuntu@<node-ip>
sudo journalctl -u rke2-server -f  # for server nodes
sudo journalctl -u rke2-agent -f   # for agent nodes
```

**Common issues:**
- SSH key permissions (must be 600)
- Network connectivity between nodes
- Firewall blocking ports 6443, 10250

### Rancher Deployment Fails

**Check Helm release:**
```bash
kubectl get helmrelease -n cattle-system
helm list -n cattle-system
```

**Check Rancher logs:**
```bash
kubectl logs -n cattle-system -l app=rancher -f
```

### Kubeconfig Not Found

Ensure SSH key path is correct:
```bash
ls -la ~/.ssh/id_rsa  # or your key
chmod 600 ~/.ssh/id_rsa
```

## Customization

### Change RKE2 Version

Edit `main.tf`:
```hcl
module "rke2_manager" {
  rke2_version = "v1.27.5"  # Specific version
}
```

### Add Agent Nodes to RKE2

Modify the cluster configuration in `terraform.tfvars`:
```hcl
clusters = {
  manager = {
    node_count = 3  # Servers
    # ...
  }
}
```

Then use the `agent_ips` variable in the rke2_cluster module.

### Change Rancher Version

Edit `terraform.tfvars`:
```hcl
rancher_version = "v2.8.0"
```

### Use Different Ingress Controller

Edit `modules/rancher_cluster/main.tf`:
```hcl
set {
  name  = "ingress.class"
  value = "nginx"  # or traefik, etc
}
```

## Next Steps

After Rancher is deployed:

1. **Access Rancher UI** and change admin password
2. **Configure SSO** (LDAP, OIDC, etc) if needed
3. **Register apps cluster** with manager cluster
4. **Deploy workloads** using Rancher
5. **Set up monitoring** (Prometheus, Grafana, etc)

## CI/CD Integration

To use in CI/CD:

```bash
# Set Terraform variables
export TF_VAR_rancher_password="<password>"
export TF_VAR_rancher_hostname="rancher.example.com"

# Deploy
terraform apply -auto-approve

# Get kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_paths | jq -r '.manager')
kubectl apply -f my-app.yaml
```

## Outputs

After deployment, view outputs:

```bash
terraform output
```

Returns:
- `cluster_ips` - IP addresses of all nodes
- `rancher_url` - Rancher access URL
- `kubeconfig_paths` - Paths to kubeconfig files
- `rancher_admin_password` - Reminder to use tfvars value
