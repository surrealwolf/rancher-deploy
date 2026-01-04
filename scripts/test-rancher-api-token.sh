#!/bin/bash
# Test Rancher API Token Creation via curl
# Run these commands manually to create and test API token

# ============================================================================
# STEP 1: Set variables (customize for your environment)
# ============================================================================

RANCHER_URL="https://rancher.example.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="your-bootstrap-password"

# Extract just the hostname for verification
HOSTNAME=$(echo "$RANCHER_URL" | sed 's|https://||' | sed 's|/$||')

echo "=========================================="
echo "Rancher API Token Creation Test"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  URL: $RANCHER_URL"
echo "  User: $ADMIN_USER"
echo "  Hostname: $HOSTNAME"
echo ""

# ============================================================================
# STEP 2: Test connectivity
# ============================================================================

echo "Step 1: Testing Rancher connectivity..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "$RANCHER_URL/health")
echo "  HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" != "200" ]; then
  echo "  ERROR: Cannot reach Rancher at $RANCHER_URL"
  echo "  Please verify:"
  echo "    - URL is correct"
  echo "    - Rancher is running"
  echo "    - DNS resolves correctly"
  exit 1
fi
echo "✓ Rancher is accessible"
echo ""

# ============================================================================
# STEP 3: Authenticate and get temporary token
# ============================================================================

echo "Step 2: Authenticating with Rancher..."
echo "  Running: curl -X POST https://$HOSTNAME/v3-public/localProviders/local?action=login"
echo ""

LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}" \
  -k "$RANCHER_URL/v3-public/localProviders/local?action=login")

echo "Response:"
echo "$LOGIN_RESPONSE" | jq . 2>/dev/null || echo "$LOGIN_RESPONSE"
echo ""

# Extract temporary token
TEMP_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null || echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TEMP_TOKEN" ] || [ "$TEMP_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get temporary token"
  echo "Troubleshooting:"
  echo "  - Check ADMIN_USER is correct (default: admin)"
  echo "  - Check ADMIN_PASSWORD matches bootstrap password"
  echo "  - Verify Rancher is fully initialized"
  exit 1
fi

echo "✓ Authentication successful"
echo "  Temp Token: ${TEMP_TOKEN:0:50}..."
echo ""

# ============================================================================
# STEP 4: Create permanent API token
# ============================================================================

echo "Step 3: Creating permanent API token..."
echo "  Running: curl -X POST https://$HOSTNAME/v3/tokens"
echo "  Using token: ${TEMP_TOKEN:0:50}..."
echo ""

TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $TEMP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "token",
    "description": "Test token via curl - can be deleted",
    "ttl": 0,
    "isDerived": false
  }' \
  -k "$RANCHER_URL/v3/tokens")

echo "Response:"
echo "$TOKEN_RESPONSE" | jq . 2>/dev/null || echo "$TOKEN_RESPONSE"
echo ""

# Extract API token
API_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token' 2>/dev/null || echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
  echo "ERROR: Failed to create API token"
  echo "Troubleshooting:"
  echo "  - Verify Rancher API is accessible"
  echo "  - Check temporary token is still valid"
  echo "  - Review Rancher logs for errors"
  exit 1
fi

echo "=========================================="
echo "✓ API Token Created Successfully!"
echo "=========================================="
echo ""
echo "API Token:"
echo "$API_TOKEN"
echo ""

# ============================================================================
# STEP 5: Verify token works
# ============================================================================

echo "Step 4: Verifying token..."
echo "  Running: curl -H 'Authorization: Bearer <token>' https://$HOSTNAME/v3/tokens"
echo ""

VERIFY_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $API_TOKEN" \
  -k "$RANCHER_URL/v3/tokens" | jq '.data | length' 2>/dev/null)

if [ -n "$VERIFY_RESPONSE" ] && [ "$VERIFY_RESPONSE" != "null" ]; then
  echo "✓ Token verified - API access working"
  echo "  Token count: $VERIFY_RESPONSE tokens in system"
else
  echo "⚠ Could not verify token (check manually)"
fi
echo ""

# ============================================================================
# STEP 6: Display next steps
# ============================================================================

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Add token to terraform/terraform.tfvars:"
echo ""
echo "   rancher_api_token = \"$API_TOKEN\""
echo ""
echo "2. Set downstream registration:"
echo ""
echo "   register_downstream_cluster = true"
echo ""
echo "3. Re-apply Terraform:"
echo ""
echo "   cd terraform && terraform apply -auto-approve"
echo ""
echo "4. View token in Rancher UI:"
echo ""
echo "   Account & Settings → API & Keys"
echo ""
echo "5. Delete token if needed (via UI or API):"
echo ""
echo "   curl -X DELETE \\"
echo "     -H \"Authorization: Bearer <api-token>\" \\"
echo "     -k https://$HOSTNAME/v3/tokens/<token-id>"
echo ""

# ============================================================================
# REFERENCE: Common curl commands
# ============================================================================

echo "=========================================="
echo "Reference: Useful curl Commands"
echo "=========================================="
echo ""

echo "List all tokens:"
echo "  curl -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "    -k $RANCHER_URL/v3/tokens"
echo ""

echo "Get specific token details:"
echo "  curl -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "    -k $RANCHER_URL/v3/tokens | jq '.data[] | select(.token==\"$API_TOKEN\")'  "
echo ""

echo "Get clusters:"
echo "  curl -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "    -k $RANCHER_URL/v3/clusters"
echo ""

echo "Create downstream cluster:"
echo "  curl -X POST \\"
echo "    -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"name\":\"my-cluster\",\"description\":\"Test cluster\"}' \\"
echo "    -k $RANCHER_URL/v3/clusters"
echo ""

echo "Delete token:"
echo "  curl -X DELETE \\"
echo "    -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "    -k $RANCHER_URL/v3/tokens/<token-id>"
echo ""
