# Manual Rancher Deployment (Verified Working)

## Summary

After successfully deploying the RKE2 clusters with Terraform, Rancher can be deployed manually using Helm. This has been tested and verified to work with self-signed certificates.

## Prerequisites

All RKE2 clusters must be operational:
- Manager cluster: 3 nodes (192.168.14.100-102)
- Apps cluster: 3 nodes (192.168.14.110-112)
- All nodes in "Ready" state

## Step 1: Retrieve and Fix Kubeconfig

RKE2 generates kubeconfigs with `127.0.0.1` which only works via SSH tunneling. We need to replace it with the actual IP:

```bash
# Get the kubeconfig from the primary manager node
ssh -i ~/.ssh/id_rsa ubuntu@192.168.14.100 "sudo cat /etc/rancher/rke2/rke2.yaml" | \
  sed 's/127.0.0.1/192.168.14.100/g' > ~/.kube/rancher-manager.yaml

# Verify access
kubectl get nodes \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify
```

**Expected output:**
```
NAME                STATUS   ROLES                AGE   VERSION
rancher-manager-1   Ready    control-plane,etcd   ...   v1.34.3+rke2r1
rancher-manager-2   Ready    control-plane,etcd   ...   v1.34.3+rke2r1
rancher-manager-3   Ready    control-plane,etcd   ...   v1.34.3+rke2r1
```

## Step 2: Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Step 3: Add Helm Repositories

```bash
# Add Jetstack (cert-manager)
helm repo add jetstack https://charts.jetstack.io

# Add Rancher
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable

# Update repos
helm repo update
```

## Step 4: Create Namespace

```bash
kubectl create namespace cattle-system \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify
```

## Step 5: Install Cert-Manager

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify \
  --set installCRDs=true \
  --wait
```

## Step 6: Install Rancher

```bash
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify \
  --set hostname=rancher.dataknife.net \
  --set replicas=3 \
  --set bootstrapPassword=change-me-to-secure-password \
  --wait --timeout 10m
```

## Step 7: Access Rancher

Get the bootstrap password:

```bash
kubectl get secret --namespace cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n"}}' \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify
```

Browse to: `https://rancher.dataknife.net`

**Username:** admin  
**Password:** (from bootstrap-secret)

## Troubleshooting

### TLS Certificate Warnings
RKE2 uses self-signed certificates. Browsers will show warnings - this is normal for self-signed certs.

### Rancher Pods Not Starting
Check pod status and logs:
```bash
kubectl get pods -n cattle-system \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify

kubectl logs -n cattle-system deployment/rancher \
  --kubeconfig=~/.kube/rancher-manager.yaml \
  --insecure-skip-tls-verify
```

### DNS Resolution Issues
If `rancher.dataknife.net` doesn't resolve:
1. Update your DNS records
2. Or add to /etc/hosts: `192.168.14.100 rancher.dataknife.net`

## Next Steps

After Rancher is deployed:

1. **Set admin password:** Login and change the bootstrap password
2. **Configure provisioning:** Set up cluster provisioning for the apps cluster
3. **Add local cluster:** Register the downstream apps cluster in Rancher

## Terraform Integration (Planned)

To automate this in Terraform:

1. Fix kubeconfig path substitution (127.0.0.1 → actual IP)
2. Add `skip_credentials_validation = true` to kubernetes provider
3. Use `helm_release` resource for cert-manager and Rancher
4. Add kubeconfig retrieval as provisioner output

See [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) for Terraform approach.
