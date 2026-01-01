# Terraform Variables Configuration

## Overview

This directory uses Terraform variable files to manage configuration across different environments. All production secrets are kept out of version control for security.

## File Structure

```
terraform/
├── terraform.tfvars.example       # Example template (IN GIT) - copy this to create production config
├── terraform.tfvars               # Production config (NOT IN GIT - gitignored)
├── environments/
│   ├── manager/
│   │   ├── terraform.tfvars.example
│   │   └── terraform.tfvars       # (NOT IN GIT)
│   └── nprd-apps/
│       ├── terraform.tfvars.example
│       └── terraform.tfvars       # (NOT IN GIT)
```

## Quick Start

### 1. Create your production variables file

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Edit with your environment values

```bash
# Use your preferred editor
vim terraform/terraform.tfvars
# OR
nano terraform/terraform.tfvars
```

### 3. Update required fields

- `proxmox_api_url`: Your Proxmox endpoint
- `proxmox_api_token_secret`: Your API token (KEEP SECRET!)
- `proxmox_node`: Target node name
- `clusters`: CPU, memory, storage settings
- `rancher_password`: Rancher admin password
- `rancher_hostname`: Rancher DNS name

### 4. Validate configuration

```bash
cd terraform
terraform validate
terraform plan
```

## Security Practices

### ✅ DO:

- ✅ Copy `.example` file to create production config
- ✅ Use environment variables for secrets:
  ```bash
  export PROXMOX_VE_API_TOKEN="terraform@pve!token=xxxxx"
  ```
- ✅ Use `.tfvars` files only locally (never in git)
- ✅ Rotate API tokens regularly
- ✅ Restrict file permissions:
  ```bash
  chmod 600 terraform.tfvars
  ```
- ✅ Use Terraform state locking in production
- ✅ Encrypt Terraform state files

### ❌ DON'T:

- ❌ Commit `terraform.tfvars` to git
- ❌ Share production values in chat/email
- ❌ Use `default` values for secrets in code
- ❌ Store tokens in shell history:
  ```bash
  # Bad:
  terraform apply -var="api_token=xxxxx"
  
  # Good:
  export PROXMOX_VE_API_TOKEN="xxxxx"
  terraform apply
  ```

## Using Different Environments

### Create environment-specific files:

```bash
# Development
cp terraform.tfvars.example terraform.tfvars.dev

# Staging
cp terraform.tfvars.example terraform.tfvars.staging

# Production
cp terraform.tfvars.example terraform.tfvars.prod
```

### Apply for specific environment:

```bash
# Development
terraform apply -var-file="terraform.tfvars.dev"

# Staging  
terraform apply -var-file="terraform.tfvars.staging"

# Production (requires approval)
terraform apply -var-file="terraform.tfvars.prod"
```

## Environment Variables

Instead of modifying `.tfvars` files, you can use environment variables:

```bash
# Proxmox configuration
export PROXMOX_VE_ENDPOINT="https://192.168.1.10:8006"
export PROXMOX_VE_API_TOKEN="terraform@pve!token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Or use terraform var override
export TF_VAR_proxmox_api_url="https://192.168.1.10:8006"
export TF_VAR_proxmox_node="pve2"

# Then apply without -var-file
terraform plan
terraform apply
```

## File Permissions

Always protect sensitive files:

```bash
# Restrict access to production files
chmod 600 terraform.tfvars
chmod 600 terraform.tfvars.prod

# Verify permissions
ls -la terraform.tfvars*
```

Expected output:
```
-rw------- terraform.tfvars
-rw-r--r-- terraform.tfvars.example
```

## Git Configuration

The `.gitignore` file already excludes:

```
# Terraform variables (all production files)
terraform.tfvars
**/terraform.tfvars
**/terraform.tfvars.prod
**/terraform.tfvars.production

# But includes examples (safe to share)
!terraform.tfvars.example
!**/terraform.tfvars.example
```

To verify git will ignore your files:

```bash
git check-ignore -v terraform/terraform.tfvars
# Should output: terraform/terraform.tfvars	.gitignore:25
```

## API Token Management

### Create Proxmox API token:

```bash
ssh root@pve2
pveum user token add terraform@pve terraform-token --privsep=0
# Output: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Format in tfvars:

```hcl
proxmox_api_token_id     = "terraform"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Or use environment variable:

```bash
export PROXMOX_VE_API_TOKEN="terraform@pve!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Common Issues

### "terraform.tfvars not found"

**Solution**: Create the file:
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### "API token invalid"

**Check**:
1. Token created correctly: `pveum user token list`
2. Format correct in tfvars: `user!tokenid=secret`
3. Token has required permissions
4. Token not expired

### "Permission denied" on variables file

**Solution**:
```bash
chmod 600 terraform.tfvars
```

### Git accidentally tracked terraform.tfvars

**Fix**:
```bash
git rm --cached terraform/terraform.tfvars
git commit -m "Remove accidentally tracked terraform.tfvars"
```

## References

- [Terraform Variables](https://www.terraform.io/language/values/variables)
- [Terraform Sensitive Data](https://www.terraform.io/language/values/variables#suppressing-values-in-cli-output)
- [Proxmox API Tokens](https://pve.proxmox.com/pve-docs/pveum.1.html)
- [Git .gitignore Patterns](https://git-scm.com/docs/gitignore)

## Support

For issues with variables:
1. Check `.gitignore` - ensure secrets not tracked
2. Verify file permissions - should be 600
3. Test with `terraform validate`
4. Check token format matches `user!tokenid=secret`
5. Review `terraform.tfvars.example` as reference
