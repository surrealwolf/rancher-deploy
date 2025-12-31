.PHONY: help init plan apply destroy validate fmt clean setup check-prereqs

# Variables
MANAGER_ENV := terraform/environments/manager
NPRD_ENV := terraform/environments/nprd-apps

help:
	@echo "Rancher on Proxmox - Terraform Management"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  check-prereqs        - Check for required tools"
	@echo "  setup                - Interactive setup wizard"
	@echo ""
	@echo "Manager Cluster:"
	@echo "  init-manager         - Initialize manager environment"
	@echo "  plan-manager         - Show manager infrastructure plan"
	@echo "  apply-manager        - Deploy manager cluster"
	@echo "  destroy-manager      - Destroy manager cluster"
	@echo "  validate-manager     - Validate manager configuration"
	@echo ""
	@echo "NPRD-Apps Cluster:"
	@echo "  init-nprd            - Initialize nprd-apps environment"
	@echo "  plan-nprd            - Show nprd-apps infrastructure plan"
	@echo "  apply-nprd           - Deploy nprd-apps cluster"
	@echo "  destroy-nprd         - Destroy nprd-apps cluster"
	@echo "  validate-nprd        - Validate nprd-apps configuration"
	@echo ""
	@echo "Utilities:"
	@echo "  fmt                  - Format all Terraform files"
	@echo "  validate             - Validate all configurations"
	@echo "  clean                - Remove Terraform cache and state"
	@echo "  help                 - Show this help message"

check-prereqs:
	@echo "Checking prerequisites..."
	@command -v terraform >/dev/null 2>&1 || { echo "terraform is required"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl is recommended"; }
	@command -v helm >/dev/null 2>&1 || { echo "helm is recommended"; }
	@echo "✓ All required tools found"

setup:
	@chmod +x setup.sh
	@./setup.sh

# Manager cluster targets
init-manager:
	@cd $(MANAGER_ENV) && terraform init

plan-manager: init-manager
	@cd $(MANAGER_ENV) && terraform plan -out=tfplan

apply-manager:
	@cd $(MANAGER_ENV) && terraform apply tfplan

destroy-manager:
	@cd $(MANAGER_ENV) && terraform destroy

validate-manager:
	@cd $(MANAGER_ENV) && terraform validate

# NPRD-Apps cluster targets
init-nprd:
	@cd $(NPRD_ENV) && terraform init

plan-nprd: init-nprd
	@cd $(NPRD_ENV) && terraform plan -out=tfplan

apply-nprd:
	@cd $(NPRD_ENV) && terraform apply tfplan

destroy-nprd:
	@cd $(NPRD_ENV) && terraform destroy

validate-nprd:
	@cd $(NPRD_ENV) && terraform validate

# Utility targets
fmt:
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive terraform/

validate:
	@echo "Validating manager configuration..."
	@cd $(MANAGER_ENV) && terraform validate
	@echo "Validating nprd-apps configuration..."
	@cd $(NPRD_ENV) && terraform validate
	@echo "✓ All configurations valid"

clean:
	@echo "Cleaning Terraform cache..."
	@find terraform -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find terraform -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find terraform -name "tfplan" -delete 2>/dev/null || true
	@echo "✓ Cleaned"

# Quick deploy all
deploy-all: plan-manager apply-manager plan-nprd apply-nprd
	@echo "✓ All clusters deployed"

# Destroy all
destroy-all:
	@echo "Warning: This will destroy ALL clusters"
	@read -p "Are you sure? (type 'yes'): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		$(MAKE) destroy-manager; \
		$(MAKE) destroy-nprd; \
		echo "✓ All clusters destroyed"; \
	else \
		echo "Aborted"; \
	fi
