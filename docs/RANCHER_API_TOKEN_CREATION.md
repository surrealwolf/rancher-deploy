# Rancher API Token Creation

The Rancher API token is automatically created during the Rancher deployment process. This document explains how the token creation works and how to use it.

## Overview

When you deploy Rancher using `terraform apply`, the deployment process automatically:

1. Installs Rancher on the manager cluster
2. Waits for Rancher to be fully operational
3. Creates an API token using the bootstrap password
4. Displays the token in the deployment output

## How It Works

### During Rancher Deployment

The `deploy-rancher.sh` script (run via Terraform) performs the following steps:

**Step 1: Authenticate with Rancher**
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"<bootstrap-password>"}' \
  https://<rancher-url>/v3-public/localProviders/local?action=login
```

**Step 2: Create API Token**
```bash
curl -X POST \
  -H "Authorization: Bearer <temp-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "token",
    "description": "Terraform automation token for downstream cluster registration",
    "ttl": 0,
    "isDerived": false
  }' \
  https://<rancher-url>/v3/tokens
```

### Token Properties

- **Description**: "Terraform automation token for downstream cluster registration"
- **TTL**: 0 (never expires)
- **isDerived**: false (not a temporary derivative token)
- **Permissions**: Full cluster access

## Deployment Workflow

### 1. Deploy Rancher

```bash
cd /home/lee/git/rancher-deploy
./scripts/apply.sh  # or: terraform apply -auto-approve
```

During deployment, you'll see output like:

```
Module: rancher_cluster / deploy-rancher.sh

✓ Rancher is ready

Testing Rancher URL accessibility...
✓ Rancher is accessible at https://rancher.example.com

Creating Rancher API token for downstream cluster registration...

Step 1: Authenticating with Rancher...
✓ Authenticated with Rancher

Step 2: Creating API token...
✓ API token created successfully

==========================================
Rancher API Token:
==========================================
token-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Token saved. Add to terraform/terraform.tfvars:
  rancher_api_token = "token-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### 2. Add Token to terraform.tfvars

Copy the token from the output and add it to your `terraform/terraform.tfvars`:

```hcl
# terraform/terraform.tfvars
rancher_api_token = "token-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
register_downstream_cluster = true
```

### 3. Re-apply Terraform

Now that the API token is configured, re-run terraform to enable downstream cluster registration:

```bash
cd terraform
terraform apply -auto-approve
```

This will:
- Create the downstream cluster object in Rancher
- Generate a registration token
- Pass credentials to downstream VMs
- VMs automatically register with Rancher Manager

## Manual Token Creation

If the automatic token creation fails or you need to create another token, use the `create-rancher-api-token.sh` script:

```bash
# From project root
./create-rancher-api-token.sh https://rancher.example.com admin your-password
```

## Troubleshooting

### API Token Not Displayed

If the token creation fails during deployment, check the deployment logs:

```bash
# View the full deployment log
tail -f terraform/terraform-*.log

# Look for "Creating Rancher API token" section
grep -A 20 "Creating Rancher API token" terraform/terraform-*.log
```

Common causes:
- Rancher not fully ready when token creation attempted
- Network connectivity issues to Rancher API
- Invalid bootstrap password

**Solution**: Create token manually:
```bash
./create-rancher-api-token.sh https://rancher.example.com admin your-password
```

### "Failed to authenticate with Rancher API"

This means the bootstrap password was incorrect.

**Solution**: 
1. Verify bootstrap password in `terraform/terraform.tfvars`
2. Check if Rancher is accessible: `curl -k https://rancher.example.com`
3. Create token manually with correct password:
   ```bash
   ./scripts/create-rancher-api-token.sh https://rancher.example.com admin correct-password
   ```

### Downstream Registration Still Not Working

If downstream cluster registration isn't working even with API token set:

1. **Verify API token is valid**:
   ```bash
   # Test token directly
   curl -H "Authorization: Bearer <token>" \
     -k https://rancher.example.com/v3/tokens
   ```

2. **Ensure token is in terraform.tfvars**:
   ```bash
   grep rancher_api_token terraform/terraform.tfvars
   ```

3. **Check register_downstream_cluster is true**:
   ```bash
   grep register_downstream_cluster terraform/terraform.tfvars
   ```

4. **Re-apply Terraform**:
   ```bash
   cd terraform
   terraform apply -auto-approve
   ```

## Accessing Rancher

Once the API token is created and downstream cluster registration is complete:

### Rancher UI

```
URL: https://<rancher-hostname>
Username: admin
Password: <bootstrap-password> (from terraform.tfvars)
```

### kubectl Access

```bash
# Use the manager kubeconfig
export KUBECONFIG=~/.kube/rancher-manager.yaml
kubectl get nodes
kubectl get pods -n cattle-system
```

### API Access

```bash
# Using curl with API token
curl -H "Authorization: Bearer <token>" \
  -k https://rancher.example.com/v3/clusters

# Using Rancher CLI (if installed)
rancher login https://rancher.example.com --token <token>
```

## Security Best Practices

### Protecting the Token

1. **Store in terraform.tfvars** (which should be in `.gitignore`)
   ```bash
   echo "terraform/terraform.tfvars" >> .gitignore
   ```

2. **Never commit to version control**
   ```bash
   # Verify it's in .gitignore
   git status terraform/terraform.tfvars
   # Should show: ignored
   ```

3. **Keep bootstrap password secure**
   - Change it immediately after initial login to Rancher UI
   - Store securely if needed for future use

### Token Rotation

To create a new token and revoke the old one:

1. **Create new token**:
   ```bash
   ./scripts/create-rancher-api-token.sh https://rancher.example.com admin password
   ```

2. **Update terraform.tfvars** with new token

3. **Delete old token** via Rancher UI:
   - Go to Account & Settings → API & Keys
   - Find the old token
   - Click delete

4. **Re-apply Terraform**:
   ```bash
   cd terraform
   terraform apply -auto-approve
   ```

## Related Documentation

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Complete deployment walkthrough
- [RANCHER_DOWNSTREAM_MANAGEMENT.md](RANCHER_DOWNSTREAM_MANAGEMENT.md) - Downstream cluster registration
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

## Script Reference

### create-rancher-api-token.sh

Manual token creation script:

```bash
./scripts/create-rancher-api-token.sh <rancher-url> <admin-user> <admin-password>

# Example
./scripts/create-rancher-api-token.sh https://rancher.example.com admin your-password
```

**What it does:**
1. Authenticates with Rancher using admin credentials
2. Creates a long-lived API token
3. Saves token to `terraform/terraform.tfvars`
4. Displays token for reference

### deploy-rancher.sh

Automatic token creation script (called during Terraform apply):

```bash
# Run by Terraform's rancher_cluster module
# Location: terraform/modules/rancher_cluster/deploy-rancher.sh
```

**When it runs:**
- After Rancher Helm chart is installed
- After Rancher deployment is ready
- After Rancher API is accessible

**What it does:**
1. Verifies Rancher is accessible
2. Authenticates with bootstrap password
3. Creates API token
4. Displays token in deployment output
5. Instructions for updating terraform.tfvars

## Manual Token Creation via curl

If the automatic token creation fails or you prefer to create the token manually, use these curl commands:

### Quick Test: Verify Rancher Connectivity

```bash
curl -k https://rancher.example.com/health
```

### Full Manual Process

**Step 1: Set Variables**
```bash
RANCHER_URL="https://rancher.example.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="your-bootstrap-password"
```

**Step 2: Get Temporary Authentication Token**
```bash
TEMP_TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}" \
  -k "$RANCHER_URL/v3-public/localProviders/local?action=login" | \
  jq -r '.token')

echo "Temp Token: $TEMP_TOKEN"
```

**Step 3: Create Permanent API Token**
```bash
API_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $TEMP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "token",
    "description": "Terraform automation token",
    "ttl": 0,
    "isDerived": false
  }' \
  -k "$RANCHER_URL/v3/tokens" | \
  jq -r '.token')

echo "API Token: $API_TOKEN"
```

**Step 4: Verify Token Works**
```bash
curl -H "Authorization: Bearer $API_TOKEN" \
  -k "$RANCHER_URL/v3/tokens" | jq '.'
```

### Complete Script

Run the automated test script from project root:

```bash
./scripts/test-rancher-api-token.sh
```

This script handles everything: connectivity testing, authentication, token creation, and verification.

### Useful curl Commands Reference

**List all tokens:**
```bash
curl -H "Authorization: Bearer <api-token>" \
  -k https://rancher.example.com/v3/tokens | jq '.data'
```

**Get clusters:**
```bash
curl -H "Authorization: Bearer <api-token>" \
  -k https://rancher.example.com/v3/clusters | jq '.data'
```

**Create downstream cluster:**
```bash
curl -X POST \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"my-cluster","description":"Test cluster"}' \
  -k https://rancher.example.com/v3/clusters | jq '.'
```

**Delete token:**
```bash
curl -X DELETE \
  -H "Authorization: Bearer <api-token>" \
  -k https://rancher.example.com/v3/tokens/<token-id>
```

### API Endpoints Summary

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/v3-public/localProviders/local?action=login` | Authenticate (returns temp token) |
| POST | `/v3/tokens` | Create API token |
| GET | `/v3/tokens` | List all tokens |
| GET | `/v3/clusters` | List all clusters |
| POST | `/v3/clusters` | Create cluster |
| DELETE | `/v3/tokens/<id>` | Delete token |

