# Rancher on Proxmox - Complete Terraform Configuration

**Version**: 1.0  
**Last Updated**: October 2025  
**Author**: Infrastructure Team

## 📋 Overview

This repository contains a complete, production-ready Terraform configuration for deploying Rancher with two Kubernetes clusters on Proxmox infrastructure.

**What's Included:**
- ✅ Automated Proxmox VM provisioning
- ✅ Two-cluster architecture (Manager + NPRD-Apps)
- ✅ Rancher server deployment
- ✅ Kubernetes integration (RKE2)
- ✅ Complete documentation and scripts
- ✅ Makefile for easy operations
- ✅ Interactive setup wizard

## 📚 Documentation

Start here based on your needs:

1. **[QUICKSTART.md](./QUICKSTART.md)** ⚡
   - **Read this first** for a 5-minute quick start
   - Common commands and immediate setup
   - Best for: Getting started quickly

2. **[README.md](./README.md)** 📖
   - Architecture overview
   - Feature descriptions
   - Module structure
   - Best for: Understanding the architecture

3. **[INFRASTRUCTURE.md](./INFRASTRUCTURE.md)** 🏗️
   - Detailed step-by-step setup guide
   - Prerequisites and preparation
   - Post-deployment configuration
   - Troubleshooting section
   - Best for: Complete understanding and detailed setup

4. **[PROJECT_SUMMARY.md](./PROJECT_SUMMARY.md)** 📊
   - High-level project overview
   - File purposes and structure
   - Quick reference
   - Best for: Project orientation

## 🚀 Quick Start (30 seconds)

```bash
# 1. Check requirements
make check-prereqs

# 2. Configure your environment
cd terraform/environments/manager && cp terraform.tfvars.example terraform.tfvars && nano terraform.tfvars
cd ../nprd-apps && cp terraform.tfvars.example terraform.tfvars && nano terraform.tfvars

# 3. Validate
make validate

# 4. Deploy
make plan-manager && make apply-manager
make plan-nprd && make apply-nprd

# 5. Install Kubernetes and Rancher (see QUICKSTART.md)
```

## 📁 Directory Structure

```
rancher/
│
├── 📄 Documentation
│   ├── README.md              ← Architecture overview
│   ├── QUICKSTART.md          ← 5-minute quick start
│   ├── INFRASTRUCTURE.md      ← Detailed setup guide
│   ├── PROJECT_SUMMARY.md     ← Project overview
│   └── INDEX.md              ← This file
│
├── 🔧 Automation
│   ├── Makefile              ← Command shortcuts
│   ├── setup.sh              ← Interactive wizard
│   └── SETUP_COMPLETE.sh     ← Setup completion
│
├── 📋 Configuration
│   └── .gitignore            ← Git ignore rules
│
├── 📦 Scripts
│   └── scripts/
│       ├── install-rke2.sh           ← Kubernetes installation
│       └── configure-kubeconfig.sh   ← Kubectl configuration
│
└── 🏗️ Terraform
    └── terraform/
        ├── provider.tf               ← Provider configuration
        ├── variables.tf              ← Input variables
        ├── outputs.tf                ← Output values
        ├── main.tf                   ← Main infrastructure
        │
        ├── modules/
        │   ├── proxmox_vm/
        │   │   ├── main.tf           ← VM provisioning logic
        │   │   └── variables.tf      ← Module variables
        │   │
        │   └── rancher_cluster/
        │       ├── main.tf           ← Rancher deployment logic
        │       └── outputs.tf        ← Module outputs
        │
        └── environments/
            ├── manager/
            │   ├── main.tf
            │   ├── variables.tf
            │   ├── backend.tf
            │   └── terraform.tfvars.example
            │
            └── nprd-apps/
                ├── main.tf
                ├── variables.tf
                ├── backend.tf
                └── terraform.tfvars.example
```

## ⚙️ Makefile Targets

```bash
make help                # Show all available targets
make check-prereqs      # Verify prerequisites
make setup              # Run interactive setup

# Manager Cluster
make init-manager       # Initialize Terraform
make plan-manager       # Show infrastructure plan
make apply-manager      # Deploy infrastructure
make destroy-manager    # Destroy infrastructure
make validate-manager   # Validate configuration

# NPRD-Apps Cluster
make init-nprd          # Initialize Terraform
make plan-nprd          # Show infrastructure plan
make apply-nprd         # Deploy infrastructure
make destroy-nprd       # Destroy infrastructure
make validate-nprd      # Validate configuration

# Utilities
make fmt                # Format all Terraform
make validate           # Validate all configs
make clean              # Remove cache/state
make deploy-all         # Deploy everything
make destroy-all        # Destroy everything
```

## 🎯 Key Clusters

### Manager Cluster
- **Purpose**: Rancher management server
- **Nodes**: 3 (master nodes)
- **Resources**: 4 CPU, 8GB RAM, 100GB disk per node
- **Network**: 192.168.1.0/24
- **Components**:
  - RKE2 Kubernetes
  - cert-manager
  - Rancher Server
  - Monitoring stack

### NPRD-Apps Cluster
- **Purpose**: Non-production applications
- **Nodes**: 3 (worker nodes)
- **Resources**: 8 CPU, 16GB RAM, 150GB disk per node
- **Network**: 192.168.2.0/24
- **Registration**: Managed by Rancher

## 🔐 Prerequisites

### Local Machine
```bash
terraform >= 1.0
ssh client
curl/wget
```

### Proxmox
```bash
Proxmox VE 6.4+
API token with VM permissions
Ubuntu 22.04 LTS template
Network connectivity
```

## 📖 Getting Started - Choose Your Path

### Path 1: I want to get started ASAP
1. Read: [QUICKSTART.md](./QUICKSTART.md) (5 min)
2. Configure: `terraform/environments/*/terraform.tfvars`
3. Deploy: `make plan-manager && make apply-manager`

### Path 2: I want to understand everything
1. Read: [README.md](./README.md)
2. Read: [INFRASTRUCTURE.md](./INFRASTRUCTURE.md)
3. Follow step-by-step setup in INFRASTRUCTURE.md
4. Deploy when ready

### Path 3: I want interactive setup
1. Run: `./setup.sh`
2. Follow the prompts
3. Review configurations
4. Deploy when ready

## 🛠️ Common Operations

### Deploy Everything
```bash
make deploy-all
```

### Check Cluster Status
```bash
export KUBECONFIG=~/.kube/rancher-manager-config
kubectl get nodes
kubectl get pods -n cattle-system
```

### Access Rancher UI
```
https://rancher.lab.local
Username: admin
Password: (from terraform.tfvars)
```

### Register New Cluster
1. In Rancher UI: Cluster Management → Add Cluster
2. Select "Import an existing cluster"
3. Run command on new cluster

### Destroy Everything
```bash
make destroy-all
```

## 📊 Infrastructure Diagram

```
┌─────────────────────────────────────────────────┐
│              Proxmox Host                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │   Manager Cluster (192.168.1.0/24)      │   │
│  │   ┌──────────┐ ┌──────────┐ ┌────────┐ │   │
│  │   │ manager- │ │ manager- │ │manager-│ │   │
│  │   │    1     │ │    2     │ │   3    │ │   │
│  │   │ 192.1.100│ │192.1.101 │ │192.1102 │   │
│  │   └─────┬────┘ └─────┬────┘ └────┬───┘ │   │
│  │         └─────────────┼──────────┘     │   │
│  │               Rancher Server           │   │
│  │            (Replica Set x 3)           │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │   NPRD-Apps Cluster (192.168.2.0/24)    │   │
│  │   ┌──────────┐ ┌──────────┐ ┌────────┐ │   │
│  │   │ nprd-    │ │ nprd-    │ │ nprd-  │ │   │
│  │   │ apps-1   │ │ apps-2   │ │ apps-3 │ │   │
│  │   │ 192.2.100│ │192.2.101 │ │192.2102 │   │
│  │   └──────────┘ └──────────┘ └────────┘ │   │
│  │         (Registered to Manager)         │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
└─────────────────────────────────────────────────┘
```

## 🔍 Verification Checklist

After deployment, verify:

- [ ] All VMs created in Proxmox
- [ ] VMs have IP addresses assigned
- [ ] SSH access working to all nodes
- [ ] Kubernetes nodes online
- [ ] Rancher pods running
- [ ] cert-manager installed
- [ ] NPRD-Apps cluster registered
- [ ] Can access Rancher UI

See [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) for detailed verification steps.

## ❓ Troubleshooting

Common issues and solutions:

| Issue | Solution |
|-------|----------|
| VMs not getting IP | Check cloud-init on template |
| Kubernetes won't start | Check CPU/memory allocation |
| Rancher UI unavailable | Wait 5-10 minutes, check cert-manager |
| Cluster not registering | Check network connectivity |
| SSH connection fails | Verify SSH key permissions |

Full troubleshooting guide in [INFRASTRUCTURE.md](./INFRASTRUCTURE.md#troubleshooting)

## 🚀 Next Steps After Deployment

1. ✅ Deploy infrastructure (Terraform)
2. ✅ Install Kubernetes (RKE2)
3. ✅ Configure Rancher (Helm)
4. 📋 Deploy applications to NPRD-Apps
5. 📋 Configure ingress controllers
6. 📋 Set up storage solutions
7. 📋 Implement monitoring/logging
8. 📋 Configure backup/disaster recovery

## 📞 Support

For help with:
- **Rancher**: See [rancher.com/docs](https://rancher.com/docs/)
- **RKE2**: See [docs.rke2.io](https://docs.rke2.io/)
- **Terraform**: See [terraform.io/docs](https://www.terraform.io/docs/)
- **Proxmox**: See [pve.proxmox.com](https://pve.proxmox.com/wiki/)

## 📝 File Reference

### Root Files
| File | Purpose |
|------|---------|
| `Makefile` | Build automation and shortcuts |
| `setup.sh` | Interactive setup wizard |
| `README.md` | Architecture overview |
| `QUICKSTART.md` | Quick start guide |
| `INFRASTRUCTURE.md` | Detailed setup guide |
| `PROJECT_SUMMARY.md` | Project summary |
| `INDEX.md` | This file |
| `.gitignore` | Git ignore rules |

### Terraform Files
| File | Purpose |
|------|---------|
| `provider.tf` | Provider configuration |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `main.tf` | Main resources |

### Modules
| Module | Purpose |
|--------|---------|
| `proxmox_vm/` | VM provisioning |
| `rancher_cluster/` | Rancher deployment |

### Environments
| Environment | Purpose |
|-------------|---------|
| `manager/` | Manager cluster config |
| `nprd-apps/` | NPRD-Apps cluster config |

### Scripts
| Script | Purpose |
|--------|---------|
| `install-rke2.sh` | Kubernetes installation |
| `configure-kubeconfig.sh` | kubectl configuration |

## 📋 Customization Examples

### Add More Nodes to Cluster
Edit `terraform/environments/nprd-apps/terraform.tfvars`:
```hcl
node_count = 5  # Increase from 3
```

### Increase Node Resources
Edit `terraform/environments/manager/terraform.tfvars`:
```hcl
cpu_cores    = 8      # Double
memory_mb    = 16384  # Double
```

### Change Rancher Version
Edit `terraform/environments/manager/terraform.tfvars`:
```hcl
rancher_version = "v2.8.0"
```

## 🎓 Learning Resources

1. **Start**: [QUICKSTART.md](./QUICKSTART.md)
2. **Understand**: [README.md](./README.md)
3. **Deep Dive**: [INFRASTRUCTURE.md](./INFRASTRUCTURE.md)
4. **Reference**: [terraform/](./terraform/) and comments

## ✨ Features Highlight

- ✅ **Infrastructure as Code**: Everything reproducible
- ✅ **Modular Design**: Easy to extend and customize
- ✅ **Multi-Cluster**: Manage multiple clusters
- ✅ **Production Ready**: Best practices included
- ✅ **Well Documented**: Guides and examples
- ✅ **Automated**: Scripts for common tasks
- ✅ **Scalable**: Easy to add/remove resources

## 📞 Quick Commands

```bash
# Check readiness
make check-prereqs

# Full setup with wizard
./setup.sh

# Deploy everything
make deploy-all

# Check status
kctx-manager
kubectl get all -A

# Clean up
make destroy-all
```

---

**Ready to get started?** Begin with [QUICKSTART.md](./QUICKSTART.md)!
