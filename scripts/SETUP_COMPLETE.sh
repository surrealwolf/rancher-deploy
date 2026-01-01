#!/bin/bash

# Make scripts executable
chmod +x setup.sh
chmod +x scripts/install-rke2.sh
chmod +x scripts/configure-kubeconfig.sh

echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review the documentation:"
echo "   - QUICKSTART.md - Get started in 5 minutes"
echo "   - README.md - Architecture overview"
echo "   - INFRASTRUCTURE.md - Detailed setup guide"
echo ""
echo "2. Configure your environment:"
echo "   cd terraform/environments/manager"
echo "   cp terraform.tfvars.example terraform.tfvars"
echo "   nano terraform.tfvars"
echo ""
echo "   cd ../nprd-apps"
echo "   cp terraform.tfvars.example terraform.tfvars"
echo "   nano terraform.tfvars"
echo ""
echo "3. Verify configuration:"
echo "   make check-prereqs"
echo "   make validate"
echo ""
echo "4. Deploy infrastructure:"
echo "   make plan-manager"
echo "   make apply-manager"
echo "   make plan-nprd"
echo "   make apply-nprd"
echo ""
echo "For more help, run: make help"
