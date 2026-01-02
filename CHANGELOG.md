# Changelog

All notable changes to Rancher Deploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features being developed

### Changed
- Updates to existing features

### Fixed
- Bug fixes

## [1.1.0] - 2026-01-01

### Added
- **Automatic Logging Infrastructure**: New `apply.sh` script with automatic `TF_LOG=debug` logging
- **Timestamped Log Files**: Deploy logs saved to `terraform/terraform-<timestamp>.log`
- **Documentation Consolidation**: Streamlined from 6 docs to 4 focused guides
  - DEPLOYMENT_GUIDE.md - Complete deployment walkthrough with logging
  - TROUBLESHOOTING.md - Issue resolution and diagnostics
  - MODULES_AND_AUTOMATION.md - Terraform modules and RKE2/Rancher automation
  - CLOUD_IMAGE_SETUP.md - Ubuntu 24.04 provisioning details
- **RKE2 Troubleshooting Guide**: Complete section on version management and common issues
- **Root-level Documentation**: CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG.md

### Changed
- **RKE2 Version Management**: Updated from non-existent "latest" to specific versions (v1.34.3+rke2r1)
- **RKE2 Installation Script**: Improved from piped curl to download+chmod+execute pattern
- **Environment Variable Handling**: Fixed `sudo -E bash -c` pattern for proper expansion
- **Cloud-Init Provisioning**: Added `wait_for_cloud_init` to ensure networking ready before RKE2
- **Provider References**: Removed deprecated custom providers (dataknife/pve, telmate/proxmox)
- **README.md**: Updated with RKE2 version emphasis, logging instructions, consolidated doc references

### Fixed
- **RKE2 404 Errors**: Resolved "latest" version download failures by using specific release tags
- **Terraform State Caching**: Cleaned state files and validated fresh deployments
- **SSH Host Key Issues**: Added `cleanup_known_hosts` provisioner for cleaner deployments
- **RKE2 Script Execution**: Fixed edge cases with piped curl installation method
- **Documentation Overlaps**: Removed duplicate content across 6 documentation files (537 lines cleaned)

### Deprecated
- Custom Proxmox providers (now using bpg/proxmox v0.90.0 exclusively)
- "latest" RKE2 version references (must use specific versions)

## [1.0.0] - 2025-12-20

### Added
- Initial release of Rancher Deploy project
- Terraform configuration for Proxmox VE
- RKE2 Kubernetes cluster deployment
- Rancher management cluster setup
- Non-production apps cluster configuration
- Cloud-init integration for Ubuntu 24.04 LTS
- Module-based Terraform structure
  - proxmox_vm module for VM creation
  - rke2_cluster module for Kubernetes setup
  - rancher_cluster module for Rancher deployment
- Comprehensive documentation suite
  - DEPLOYMENT_GUIDE.md
  - TERRAFORM_VARIABLES.md
  - TROUBLESHOOTING.md
  - CLOUD_IMAGE_SETUP.md
- Example configurations and templates
- GitIgnore patterns for sensitive data

### Features
- ✅ Full automation from VMs to Rancher
- ✅ Cloud image provisioning (Ubuntu 24.04 LTS)
- ✅ bpg/proxmox v0.90.0 provider with reliable task polling
- ✅ RKE2 Kubernetes v1.34.3+rke2r1
- ✅ High availability 3-node clusters
- ✅ Cloud-init networking, DNS, hostnames
- ✅ Secure API token authentication
- ✅ Comprehensive troubleshooting guides

---

For detailed changes, see the [Git commit history](https://github.com/surrealwolf/rancher-deploy/commits/main).
