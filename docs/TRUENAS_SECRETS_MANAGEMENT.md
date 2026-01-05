# TrueNAS Secrets Management

## Overview

TrueNAS API keys and configuration are stored in **Terraform variables** (`terraform/terraform.tfvars`) for centralized secret management. The Helm values file is auto-generated from these Terraform variables.

## Architecture

```
terraform/terraform.tfvars (source of truth)
    ↓
scripts/generate-helm-values-from-tfvars.sh
    ↓
helm-values/democratic-csi-truenas.yaml (generated)
    ↓
Helm installation uses generated values
```

## Configuration Location

### Source: `terraform/terraform.tfvars`

All TrueNAS secrets and configuration are stored here:

```hcl
# TrueNAS hostname or IP address
truenas_host = "truenas.example.com"

# TrueNAS API key (obtain from TrueNAS UI: System → API Keys → Add)
truenas_api_key = "your-api-key-here"

# TrueNAS dataset path for NFS storage
truenas_dataset = "/mnt/pool/dataset"

# TrueNAS username (for reference/documentation)
truenas_user = "csi-user"

# TrueNAS API protocol (https recommended)
truenas_protocol = "https"

# TrueNAS API port (443 for HTTPS, 80 for HTTP)
truenas_port = 443

# Allow insecure TLS (set to true if using self-signed certificate)
truenas_allow_insecure = false

# Storage class name for democratic-csi
csi_storage_class_name = "truenas-nfs"

# Make this storage class the default (only one default allowed per cluster)
csi_storage_class_default = true
```

### Generated: `helm-values/democratic-csi-truenas.yaml`

This file is **auto-generated** from `terraform.tfvars`. Do not edit it manually - it will be overwritten.

## Workflow

### 1. Update Secrets

Edit `terraform/terraform.tfvars`:

```bash
vim terraform/terraform.tfvars
# Update truenas_api_key or other values
```

### 2. Generate Helm Values

Run the generation script:

```bash
./scripts/generate-helm-values-from-tfvars.sh
```

This will:
- Read values from `terraform/terraform.tfvars`
- Generate `helm-values/democratic-csi-truenas.yaml`
- Validate required fields

### 3. Install/Update democratic-csi

Use the generated Helm values:

```bash
export KUBECONFIG=~/.kube/nprd-apps.yaml
./scripts/install-democratic-csi.sh
```

Or manually:

```bash
helm upgrade --install democratic-csi democratic-csi/democratic-csi \
  --namespace democratic-csi \
  --create-namespace \
   -f helm-values/democratic-csi-truenas.yaml
```

## Security

### Git Ignore

Both files are gitignored:
- ✅ `terraform/terraform.tfvars` - Contains all secrets
- ✅ `helm-values/democratic-csi-truenas.yaml` - Contains API key

### Example Files

Example files (without secrets) are tracked in git:
- ✅ `terraform/terraform.tfvars.example` - Template for tfvars

Note: Helm values are generated from `terraform.tfvars` using `scripts/generate-helm-values-from-tfvars.sh`, so no example Helm values file is needed.

### Best Practices

1. **Never commit secrets** - Both files are in `.gitignore`
2. **Use example files** - Share configuration structure without secrets
3. **Rotate API keys** - Update `terraform.tfvars` and regenerate Helm values
4. **Version control** - Use Terraform state encryption for production
5. **Access control** - Limit who can read `terraform.tfvars`

## Terraform Variables

All TrueNAS variables are defined in `terraform/variables.tf`:

- `truenas_host` - TrueNAS hostname
- `truenas_api_key` - API key (sensitive)
- `truenas_dataset` - Dataset path
- `truenas_user` - Username
- `truenas_protocol` - Protocol (https/http)
- `truenas_port` - API port
- `truenas_allow_insecure` - Allow self-signed certs
- `csi_storage_class_name` - Storage class name
- `csi_storage_class_default` - Make it default

## Terraform Outputs

Terraform outputs are available in `terraform/outputs.tf`:

```bash
cd terraform
terraform output truenas_config
terraform output -json truenas_config
```

Note: API key is marked as sensitive and won't be displayed in outputs.

## Troubleshooting

### Helm values file is outdated

If you've updated `terraform.tfvars` but Helm values haven't changed:

```bash
./scripts/generate-helm-values-from-tfvars.sh
```

### API key not working

1. Verify API key in TrueNAS UI: System → API Keys
2. Check `terraform.tfvars` has correct value
3. Regenerate Helm values: `./scripts/generate-helm-values-from-tfvars.sh`
4. Reinstall democratic-csi

### Missing required values

The generation script will error if required values are missing:

```bash
Error: Missing required TrueNAS configuration in terraform.tfvars
Required: truenas_host, truenas_api_key, truenas_dataset
```

Fix by adding missing values to `terraform/terraform.tfvars`.

## Migration from Manual Configuration

If you previously edited `helm-values/democratic-csi-truenas.yaml` manually:

1. **Extract values** from the Helm values file
2. **Add to terraform.tfvars**:
   ```hcl
   truenas_host = "truenas.example.com"
   truenas_api_key = "your-api-key"
   truenas_dataset = "/mnt/SAS/RKE2"
   # ... etc
   ```
3. **Generate new Helm values**:
   ```bash
   ./scripts/generate-helm-values-from-tfvars.sh
   ```
4. **Verify** the generated file matches your needs
5. **Delete** the old manual Helm values file (it will be regenerated)

## Summary

- ✅ **Single source of truth**: `terraform/terraform.tfvars`
- ✅ **Auto-generated**: Helm values from Terraform variables
- ✅ **Secure**: Both files gitignored
- ✅ **Workflow**: Edit tfvars → Generate → Install
