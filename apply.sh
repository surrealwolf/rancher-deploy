#!/bin/bash
set -e
cd /home/lee/git/rancher-deploy/terraform
echo "Starting Terraform apply for RKE2 deployment..."
echo "This will take approximately 15-20 minutes."
echo ""
terraform apply -auto-approve
echo ""
echo "✓ Deployment complete!"
echo ""
echo "Kubeconfig files created at:"
echo "  - ~/.kube/rancher-manager.yaml"
echo "  - ~/.kube/nprd-apps.yaml"
