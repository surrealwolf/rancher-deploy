#!/bin/bash

# Rancher on Proxmox - Terraform Setup Script
# This script helps set up the Terraform configuration for Rancher deployment

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENVIRONMENTS_DIR="$SCRIPT_DIR/terraform/environments"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    else
        print_success "Terraform $(terraform version -json | jq -r '.terraform_version')"
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    else
        print_success "jq installed"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not found (will need for cluster management)"
    else
        print_success "kubectl installed"
    fi
    
    if ! command -v helm &> /dev/null; then
        print_warning "helm not found (will need for Rancher installation)"
    else
        print_success "helm installed"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Check SSH key
    if [ ! -f ~/.ssh/id_rsa ]; then
        print_warning "SSH key not found at ~/.ssh/id_rsa"
        echo "You can generate one with: ssh-keygen -t rsa -b 4096"
    else
        print_success "SSH key found"
    fi
    
    return 0
}

# Initialize environment
init_environment() {
    local env=$1
    local env_path="$ENVIRONMENTS_DIR/$env"
    
    if [ ! -d "$env_path" ]; then
        print_error "Environment directory not found: $env_path"
        return 1
    fi
    
    print_header "Initializing $env environment"
    
    # Copy tfvars if not exists
    if [ ! -f "$env_path/terraform.tfvars" ]; then
        if [ -f "$env_path/terraform.tfvars.example" ]; then
            cp "$env_path/terraform.tfvars.example" "$env_path/terraform.tfvars"
            print_success "Created terraform.tfvars (from example)"
            print_warning "Please edit $env_path/terraform.tfvars with your values"
        else
            print_error "No terraform.tfvars.example found"
            return 1
        fi
    else
        print_success "terraform.tfvars already exists"
    fi
    
    # Initialize Terraform
    cd "$env_path"
    terraform init
    print_success "Terraform initialized for $env"
    cd - > /dev/null
}

# Validate configuration
validate_environment() {
    local env=$1
    local env_path="$ENVIRONMENTS_DIR/$env"
    
    print_header "Validating $env environment"
    
    cd "$env_path"
    
    # Check if variables are set
    if grep -q "your-" terraform.tfvars; then
        print_error "Please update terraform.tfvars with actual values (replace 'your-' placeholders)"
        return 1
    fi
    
    # Validate Terraform
    terraform validate
    print_success "Configuration validated"
    
    cd - > /dev/null
}

# Show plan
show_plan() {
    local env=$1
    local env_path="$ENVIRONMENTS_DIR/$env"
    
    print_header "Terraform plan for $env"
    
    cd "$env_path"
    terraform plan -out=tfplan
    echo ""
    print_success "Plan saved to tfplan"
    cd - > /dev/null
}

# Deploy infrastructure
deploy_environment() {
    local env=$1
    local env_path="$ENVIRONMENTS_DIR/$env"
    
    print_header "Deploying $env cluster"
    
    read -p "Are you sure you want to deploy $env? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Deployment cancelled"
        return 0
    fi
    
    cd "$env_path"
    terraform apply tfplan 2>&1 | tee -a ../../../terraform_deploy.log
    print_success "$env cluster deployed"
    cd - > /dev/null
}

# Show outputs
show_outputs() {
    local env=$1
    local env_path="$ENVIRONMENTS_DIR/$env"
    
    print_header "Outputs for $env"
    
    cd "$env_path"
    terraform output
    cd - > /dev/null
}

# Main menu
show_menu() {
    echo ""
    echo "Rancher on Proxmox - Terraform Setup"
    echo "====================================="
    echo "1. Check prerequisites"
    echo "2. Initialize manager environment"
    echo "3. Initialize nprd-apps environment"
    echo "4. Validate manager configuration"
    echo "5. Validate nprd-apps configuration"
    echo "6. Show manager plan"
    echo "7. Show nprd-apps plan"
    echo "8. Deploy manager cluster"
    echo "9. Deploy nprd-apps cluster"
    echo "10. Show manager outputs"
    echo "11. Show nprd-apps outputs"
    echo "12. Exit"
    echo ""
}

# Main loop
main() {
    while true; do
        show_menu
        read -p "Select option: " option
        
        case $option in
            1) check_prerequisites ;;
            2) init_environment "manager" ;;
            3) init_environment "nprd-apps" ;;
            4) validate_environment "manager" ;;
            5) validate_environment "nprd-apps" ;;
            6) show_plan "manager" ;;
            7) show_plan "nprd-apps" ;;
            8) show_plan "manager" && deploy_environment "manager" ;;
            9) show_plan "nprd-apps" && deploy_environment "nprd-apps" ;;
            10) show_outputs "manager" ;;
            11) show_outputs "nprd-apps" ;;
            12) 
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

# Run main
main
