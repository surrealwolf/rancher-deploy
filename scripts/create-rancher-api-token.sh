#!/bin/bash

# Create Rancher API Token via Rancher API
# This script creates a long-lived API token for Terraform automation
# 
# Usage: ./create-rancher-api-token.sh <rancher-url> <admin-username> <admin-password>
# Example: ./create-rancher-api-token.sh https://rancher.example.com admin admin-password

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
RANCHER_URL="${1:-https://rancher.example.com}"
ADMIN_USER="${2:-admin}"
ADMIN_PASSWORD="${3:-}"
TOKEN_NAME="terraform-token-$(date +%s)"
TOKEN_DESCRIPTION="Terraform automation token for downstream cluster registration"

# Validate inputs
if [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${RED}Error: Admin password required${NC}"
    echo "Usage: $0 <rancher-url> <admin-username> <admin-password>"
    echo "Example: $0 https://rancher.example.com admin your-password"
    exit 1
fi

echo -e "${YELLOW}Creating Rancher API Token...${NC}"
echo "  Rancher URL: $RANCHER_URL"
echo "  Admin User: $ADMIN_USER"
echo "  Token Name: $TOKEN_NAME"

# Step 1: Get login token (temporary, for initial auth)
echo -e "\n${YELLOW}Step 1: Authenticating with Rancher...${NC}"

LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}" \
  -k "$RANCHER_URL/v3-public/localProviders/local?action=login")

# Extract token from response
TEMP_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TEMP_TOKEN" ]; then
    echo -e "${RED}Error: Failed to authenticate with Rancher${NC}"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Authentication successful${NC}"

# Step 2: Create API token
echo -e "\n${YELLOW}Step 2: Creating API token in Rancher...${NC}"

TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $TEMP_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"token\",
    \"description\": \"$TOKEN_DESCRIPTION\",
    \"ttl\": 0,
    \"isDerived\": false
  }" \
  -k "$RANCHER_URL/v3/tokens")

# Extract the API token
API_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}Error: Failed to create API token${NC}"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ API token created successfully${NC}"

# Step 3: Display the token
echo -e "\n${GREEN}=== Rancher API Token ===${NC}"
echo "Token: $API_TOKEN"
echo ""

# Step 4: Save to terraform.tfvars
echo -e "${YELLOW}Step 3: Updating terraform.tfvars...${NC}"

if [ -f "terraform/terraform.tfvars" ]; then
    # Check if rancher_api_token already exists
    if grep -q "rancher_api_token" "terraform/terraform.tfvars"; then
        # Update existing value
        sed -i "s/rancher_api_token = .*/rancher_api_token = \"$API_TOKEN\"/" "terraform/terraform.tfvars"
        echo -e "${GREEN}✓ Updated rancher_api_token in terraform.tfvars${NC}"
    else
        # Add new variable
        echo "" >> "terraform/terraform.tfvars"
        echo "# Rancher API token for downstream cluster registration" >> "terraform/terraform.tfvars"
        echo "rancher_api_token = \"$API_TOKEN\"" >> "terraform/terraform.tfvars"
        echo -e "${GREEN}✓ Added rancher_api_token to terraform.tfvars${NC}"
    fi
else
    echo -e "${RED}Error: terraform/terraform.tfvars not found${NC}"
    echo -e "${YELLOW}Manually add this to your terraform.tfvars:${NC}"
    echo "rancher_api_token = \"$API_TOKEN\""
    exit 1
fi

# Step 5: Summary
echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo "The API token has been:"
echo "  ✓ Created in Rancher"
echo "  ✓ Saved to terraform/terraform.tfvars"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review terraform.tfvars to confirm the token was added"
echo "  2. Set register_downstream_cluster = true in terraform.tfvars"
echo "  3. Run: cd terraform && terraform apply"
echo ""
echo -e "${YELLOW}Token Details:${NC}"
echo "  Name: $TOKEN_NAME"
echo "  Description: $TOKEN_DESCRIPTION"
echo "  TTL: Never expires"
echo "  Rancher URL: $RANCHER_URL"
