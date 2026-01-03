.PHONY: help init plan apply destroy destroy-quick validate fmt clean check-prereqs check-rancher-tools

# Terraform directory
TF_DIR := terraform

help:
	@echo "Rancher on Proxmox - Terraform Management"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  check-prereqs        - Check for required tools (terraform, curl, ssh, jq)"
	@echo "  check-rancher-tools  - Check for Rancher deployment tools (helm, kubectl)"
	@echo ""
	@echo "Terraform Operations:"
	@echo "  init                 - Initialize Terraform"
	@echo "  plan                 - Show infrastructure plan"
	@echo "  apply                - Deploy infrastructure with logging"
	@echo "  destroy              - Destroy infrastructure (interactive)"
	@echo "  destroy-quick        - Destroy without confirmation"
	@echo "  validate             - Validate Terraform configuration"
	@echo "  fmt                  - Format Terraform files"
	@echo "  clean                - Remove Terraform cache and state"
	@echo "  help                 - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  1. make check-prereqs    - Verify tools are installed"
	@echo "  2. make init             - Initialize Terraform"
	@echo "  3. make plan             - Preview changes"
	@echo "  4. make apply            - Deploy infrastructure"

check-prereqs:
	@echo "Checking prerequisites..."
	@echo ""
	@MISSING_TOOLS=0; \
	TOOLS="terraform curl ssh jq"; \
	for tool in $$TOOLS; do \
	  if ! command -v $$tool >/dev/null 2>&1; then \
	    echo "✗ $$tool is required but not installed"; \
	    MISSING_TOOLS=1; \
	  else \
	    echo "✓ $$tool found"; \
	  fi; \
	done; \
	if [ $$MISSING_TOOLS -eq 1 ]; then \
	  echo ""; \
	  echo "Installation instructions:"; \
	  echo "  Ubuntu/Debian:"; \
	  echo "    sudo apt-get update && sudo apt-get install -y curl openssh-client jq"; \
	  echo "    wget https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"; \
	  echo "    sudo apt-get install -y terraform"; \
	  echo "  macOS (with Homebrew):"; \
	  echo "    brew install terraform curl openssh jq"; \
	  echo "  Or download directly:"; \
	  echo "    Terraform: https://www.terraform.io/downloads"; \
	  exit 1; \
	fi; \
	echo ""; \
	echo "✓ All required tools found"

check-rancher-tools:
	@echo "Checking Rancher deployment tools..."
	@echo ""
	@MISSING_TOOLS=0; \
	TOOLS="helm kubectl"; \
	for tool in $$TOOLS; do \
	  if ! command -v $$tool >/dev/null 2>&1; then \
	    echo "✗ $$tool is required for Rancher deployment but not installed"; \
	    MISSING_TOOLS=1; \
	  else \
	    echo "✓ $$tool found"; \
	  fi; \
	done; \
	if [ $$MISSING_TOOLS -eq 1 ]; then \
	  echo ""; \
	  echo "Installation instructions:"; \
	  echo "  helm (Kubernetes package manager):"; \
	  echo "    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"; \
	  echo "    Or: brew install helm (macOS)"; \
	  echo ""; \
	  echo "  kubectl (Kubernetes CLI):"; \
	  echo "    curl -LO \"https://dl.k8s.io/release/\$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""; \
	  echo "    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"; \
	  echo "    Or: brew install kubectl (macOS)"; \
	  exit 1; \
	fi; \
	echo ""; \
	echo "✓ All Rancher tools found"

# Terraform targets
init: check-prereqs
	@cd $(TF_DIR) && terraform init

plan: init
	@cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	@./apply.sh

destroy:
	@./destroy.sh

destroy-quick:
	@echo "⚠️  Quick destroy without confirmation (use with caution!)"
	@cd $(TF_DIR) && terraform destroy -auto-approve -parallelism=3
	@rm -fv $(TF_DIR)/.manager-token 2>/dev/null || true
	@rm -fv ~/.kube/rancher-manager.yaml 2>/dev/null || true
	@echo "✓ Infrastructure destroyed"

validate:
	@cd $(TF_DIR) && terraform validate

fmt:
	@cd $(TF_DIR) && terraform fmt -recursive

clean:
	@cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl tfplan terraform.tfstate*
	@echo "✓ Cleaned"

.DEFAULT_GOAL := help
