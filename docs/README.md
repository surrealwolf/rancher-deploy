# Rancher on Proxmox - Documentation

Complete documentation for deploying Rancher Kubernetes clusters on Proxmox using Terraform.

## Quick Navigation

### Getting Started
- **[DEPLOYMENT_READY.md](DEPLOYMENT_READY.md)** - Pre-deployment checklist and final status
- **[TERRAFORM_READY_TO_DEPLOY.md](TERRAFORM_READY_TO_DEPLOY.md)** - Quick start guide for deployment

### Planning & Architecture
- **[PROXMOX_MCP_TEMPLATE_REVIEW.md](PROXMOX_MCP_TEMPLATE_REVIEW.md)** - Architecture review and planning
- **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** - Complete project overview

### Implementation
- **[TEMPLATE_CREATION_IMPLEMENTATION.md](TEMPLATE_CREATION_IMPLEMENTATION.md)** - Step-by-step VM template creation
- **[TEMPLATE_CREATION_COMPLETE.md](TEMPLATE_CREATION_COMPLETE.md)** - Template creation summary

### Deployment
- **[TERRAFORM_DEPLOYMENT_GUIDE.md](TERRAFORM_DEPLOYMENT_GUIDE.md)** - Comprehensive Terraform deployment guide
  - Prerequisites
  - Configuration examples
  - Troubleshooting section
  - Post-deployment steps

## Infrastructure Overview

```
Proxmox Cluster (pve2)
├── Template VM (ID 400)
│   └── ubuntu-22.04-template
│
├── Manager Cluster (401-403)
│   ├── rancher-manager-1 (192.168.1.100)
│   ├── rancher-manager-2 (192.168.1.101)
│   └── rancher-manager-3 (192.168.1.102)
│       └─ Rancher Server, cert-manager
│
└── NPRD-Apps Cluster (404-406)
    ├── nprd-apps-1 (192.168.2.100)
    ├── nprd-apps-2 (192.168.2.101)
    └── nprd-apps-3 (192.168.2.102)
        └─ Kubernetes workers
```

## Key Technologies

| Component | Version |
|-----------|---------|
| Proxmox VE | 6.4+ |
| Ubuntu | 22.04 LTS |
| RKE2 | Latest |
| Rancher | v2.7.7 |
| Terraform | v1.14.3 |
| Kubernetes | v1.27+ |

## Deployment Workflow

1. **Review Architecture** - Read PROXMOX_MCP_TEMPLATE_REVIEW.md
2. **Create Infrastructure** - Follow TEMPLATE_CREATION_IMPLEMENTATION.md
3. **Configure Terraform** - Use TERRAFORM_READY_TO_DEPLOY.md
4. **Deploy Clusters** - Execute TERRAFORM_DEPLOYMENT_GUIDE.md
5. **Verify** - Check DEPLOYMENT_READY.md

## File Structure

```
rancher-deploy/
├── docs/                           # This directory
│   ├── README.md                   # Documentation index
│   ├── DEPLOYMENT_READY.md
│   ├── PROJECT_SUMMARY.md
│   ├── PROXMOX_MCP_TEMPLATE_REVIEW.md
│   ├── TEMPLATE_CREATION_COMPLETE.md
│   ├── TEMPLATE_CREATION_IMPLEMENTATION.md
│   ├── TERRAFORM_DEPLOYMENT_GUIDE.md
│   └── TERRAFORM_READY_TO_DEPLOY.md
├── terraform/                      # Terraform IaC
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── proxmox_vm/
│   │   └── rancher_cluster/
│   └── environments/
│       ├── manager/
│       └── nprd-apps/
└── scripts/
    ├── install-rke2.sh
    └── configure-kubeconfig.sh
```

## Quick Commands

### Initialize Terraform
```bash
cd terraform
terraform init
```

### Validate Configuration
```bash
terraform validate
terraform plan
```

### Deploy
```bash
terraform apply
```

### Access Rancher
```
URL: https://rancher.lab.local
Username: admin
Password: (from terraform.tfvars)
```

## Support & Troubleshooting

Refer to the **Troubleshooting** sections in:
- TEMPLATE_CREATION_IMPLEMENTATION.md - For VM creation issues
- TERRAFORM_DEPLOYMENT_GUIDE.md - For deployment issues

## Status

✅ **All documentation complete**
✅ **Infrastructure designed**
✅ **Terraform configured**

Ready for deployment!

