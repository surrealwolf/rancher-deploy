.PHONY: help init plan apply destroy validate fmt clean check-prereqs

# Terraform directory
TF_DIR := terraform

help:
	@echo "Rancher on Proxmox - Terraform Management"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  check-prereqs        - Check for required tools"
	@echo ""
	@echo "Terraform Operations:"
	@echo "  init                 - Initialize Terraform"
	@echo "  plan                 - Show infrastructure plan"
	@echo "  apply                - Deploy infrastructure (both clusters)"
	@echo "  destroy              - Destroy infrastructure"
	@echo "  validate             - Validate Terraform configuration"
	@echo "  fmt                  - Format Terraform files"
	@echo "  clean                - Remove Terraform cache and state"
	@echo "  help                 - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  1. make init       - Initialize Terraform"
	@echo "  2. make plan       - Preview changes"
	@echo "  3. make apply      - Deploy infrastructure"

check-prereqs:
	@echo "Checking prerequisites..."
	@command -v terraform >/dev/null 2>&1 || { echo "terraform is required"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
	@echo "✓ All required tools found"

# Terraform targets
init: check-prereqs
	@cd $(TF_DIR) && terraform init

plan: init
	@cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	@cd $(TF_DIR) && terraform apply tfplan

destroy:
	@echo "Warning: This will destroy ALL infrastructure"
	@read -p "Are you sure? (type 'yes'): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd $(TF_DIR) && terraform destroy; \
	else \
		echo "Aborted"; \
	fi

validate:
	@cd $(TF_DIR) && terraform validate

fmt:
	@cd $(TF_DIR) && terraform fmt -recursive

clean:
	@cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl tfplan terraform.tfstate*
	@echo "✓ Cleaned"

.DEFAULT_GOAL := help
