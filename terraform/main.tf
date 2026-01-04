# ============================================================================
# DOWNLOAD UBUNTU CLOUD IMAGE ONCE AT ROOT LEVEL
# Reused by all VM modules instead of downloading multiple times
# ============================================================================

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type        = "import"
  datastore_id        = "images-import"
  node_name           = var.proxmox_node
  url                 = var.ubuntu_cloud_image_url
  file_name           = "ubuntu-noble-cloudimg-amd64.qcow2"
  overwrite           = true
  overwrite_unmanaged = true
}

# ============================================================================
# LOCAL VALUES FOR CLUSTER CONFIGURATION
# ============================================================================

locals {
  # Dynamically determine downstream cluster name (first non-manager cluster)
  downstream_cluster_name = var.downstream_cluster_name != "" ? var.downstream_cluster_name : [
    for name in keys(var.clusters) : name if name != "manager"
  ][0]
}

# ============================================================================
# RANCHER MANAGER CLUSTER - PRIMARY NODE (manager-1)
# Builds first, initializes RKE2, generates cluster token
# ============================================================================

module "rancher_manager_primary" {
  source = "./modules/proxmox_vm"

  vm_name               = "rancher-manager-1"
  vm_id                 = var.vm_id_start_manager
  proxmox_node          = var.proxmox_node
  cloud_image_datastore = proxmox_virtual_environment_download_file.ubuntu_cloud_image.datastore_id
  cloud_image_file_name = proxmox_virtual_environment_download_file.ubuntu_cloud_image.file_name
  datastore_id          = var.clusters["manager"].storage

  cpu_cores    = var.clusters["manager"].cpu_cores
  memory_mb    = var.clusters["manager"].memory_mb
  disk_size_gb = var.clusters["manager"].disk_size_gb

  hostname    = "rancher-manager-1"
  ip_address  = "${var.clusters["manager"].ip_subnet}.${var.clusters["manager"].ip_start_octet}/24"
  gateway     = var.clusters["manager"].gateway
  dns_servers = var.clusters["manager"].dns_servers
  domain      = var.clusters["manager"].domain
  vlan_id     = var.clusters["manager"].vlan_id

  ssh_private_key = var.ssh_private_key

  # RKE2 configuration - primary server (standalone, generates token)
  rke2_enabled       = true
  rke2_version       = "v1.34.3+rke2r1"
  is_rke2_server     = true
  rke2_is_primary    = true  # NEW: marks this as primary node
  rke2_server_token  = ""    # Primary generates its own token
  rke2_server_ip     = ""    # No upstream server for primary
  cluster_hostname   = var.manager_cluster_hostname
  cluster_primary_ip = var.manager_cluster_primary_ip
  cluster_aliases    = var.manager_cluster_aliases

  depends_on = [
    proxmox_virtual_environment_download_file.ubuntu_cloud_image
  ]
}

# ============================================================================
# MANAGER CLUSTER - FETCH TOKEN FROM PRIMARY
# Fetches RKE2 token from primary node and stores locally
# ============================================================================

locals {
  manager_primary_ip = split("/", module.rancher_manager_primary.ip_address)[0]
  manager_token_file = "${abspath("${path.root}/../config")}/.manager-token"
}

resource "null_resource" "fetch_manager_token" {
  provisioner "local-exec" {
    command = "bash ${path.module}/fetch-token.sh ${var.ssh_private_key} ${local.manager_primary_ip} ${local.manager_token_file}"
  }

  # Clean up token file on destroy
  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "rm -f ${pathexpand("${path.root}/../config")}/.manager-token"
  }

  depends_on = [
    module.rancher_manager_primary
  ]
}

# Read the token back from file (optional - may not exist during destroy)
# Using simple local read instead of trying to check with fileexists()
data "local_file" "manager_token" {
  count    = 1
  filename = local.manager_token_file
  depends_on = [
    null_resource.fetch_manager_token
  ]
}

# ============================================================================
# RANCHER MANAGER CLUSTER - SECONDARY NODES (manager-2, manager-3)
# Only builds after primary is ready and token is fetched
# ============================================================================

module "rancher_manager_additional" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(1, var.clusters["manager"].node_count) :
    "manager-${i + 1}" => {
      vm_id          = var.vm_id_start_manager + i
      hostname       = "rancher-manager-${i + 1}"
      ip_address     = "${var.clusters["manager"].ip_subnet}.${var.clusters["manager"].ip_start_octet + i}/24"
      node_index     = i
    }
  }

  vm_name               = each.value.hostname
  vm_id                 = each.value.vm_id
  proxmox_node          = var.proxmox_node
  cloud_image_datastore = proxmox_virtual_environment_download_file.ubuntu_cloud_image.datastore_id
  cloud_image_file_name = proxmox_virtual_environment_download_file.ubuntu_cloud_image.file_name
  datastore_id          = var.clusters["manager"].storage

  cpu_cores    = var.clusters["manager"].cpu_cores
  memory_mb    = var.clusters["manager"].memory_mb
  disk_size_gb = var.clusters["manager"].disk_size_gb

  hostname    = each.value.hostname
  ip_address  = each.value.ip_address
  gateway     = var.clusters["manager"].gateway
  dns_servers = var.clusters["manager"].dns_servers
  domain      = var.clusters["manager"].domain
  vlan_id     = var.clusters["manager"].vlan_id

  ssh_private_key = var.ssh_private_key

  # RKE2 configuration - secondary servers (join primary's cluster)
  rke2_enabled       = true
  rke2_version       = "v1.34.3+rke2r1"
  is_rke2_server     = true
  rke2_is_primary    = false  # NEW: marks this as secondary node
  rke2_server_token  = try(trimspace(data.local_file.manager_token[0].content), "")  # Token fetched locally from primary
  rke2_server_ip     = local.manager_primary_ip  # Primary IP
  cluster_hostname   = var.manager_cluster_hostname
  cluster_primary_ip = var.manager_cluster_primary_ip
  cluster_aliases    = var.manager_cluster_aliases

  # CRITICAL: Only build after primary is ready AND token is fetched
  depends_on = [
    module.rancher_manager_primary,
    data.local_file.manager_token
  ]
}

# ============================================================================
# MANAGER CLUSTER - VERIFICATION & KUBECONFIG
# Waits for all manager nodes to be ready, retrieves kubeconfig
# ============================================================================

module "rke2_manager" {
  source = "./modules/rke2_manager_cluster"

  cluster_name         = "rancher-manager"
  cluster_hostname     = var.manager_cluster_hostname  # Use FQDN instead of IP
  server_ips           = concat(
    [split("/", module.rancher_manager_primary.ip_address)[0]],
    [for node in module.rancher_manager_additional : split("/", node.ip_address)[0]]
  )
  ssh_private_key_path = var.ssh_private_key
  ssh_user             = "ubuntu"

  depends_on = [
    module.rancher_manager_primary,
    module.rancher_manager_additional
  ]
}

# ============================================================================
# NPRD APPS CLUSTER - FETCH TOKEN FROM PRIMARY
# Fetches RKE2 token from apps primary node and stores locally
# ============================================================================

locals {
  nprd_apps_primary_ip = split("/", module.nprd_apps_primary.ip_address)[0]
  nprd_apps_token_file = "${abspath("${path.root}/../config")}/.nprd-apps-token"
}

resource "null_resource" "fetch_nprd_apps_token" {
  provisioner "local-exec" {
    command = "bash ${path.module}/fetch-token.sh ${var.ssh_private_key} ${local.nprd_apps_primary_ip} ${local.nprd_apps_token_file}"
  }

  depends_on = [
    module.nprd_apps_primary
  ]
}

# Read the nprd-apps token back from file (optional - may not exist during destroy)
data "local_file" "nprd_apps_token" {
  count    = 1
  filename = local.nprd_apps_token_file
  depends_on = [
    null_resource.fetch_nprd_apps_token
  ]
}

# ============================================================================
# NPRD APPS CLUSTER - PRIMARY NODE (apps-1)
# Only builds after manager cluster is ready
# ============================================================================

module "nprd_apps_primary" {
  source = "./modules/proxmox_vm"

  vm_name               = "nprd-apps-1"
  vm_id                 = var.vm_id_start_apps
  proxmox_node          = var.proxmox_node
  cloud_image_datastore = proxmox_virtual_environment_download_file.ubuntu_cloud_image.datastore_id
  cloud_image_file_name = proxmox_virtual_environment_download_file.ubuntu_cloud_image.file_name
  datastore_id          = var.clusters["nprd-apps"].storage

  cpu_cores    = var.clusters["nprd-apps"].cpu_cores
  memory_mb    = var.clusters["nprd-apps"].memory_mb
  disk_size_gb = var.clusters["nprd-apps"].disk_size_gb

  hostname    = "nprd-apps-1"
  ip_address  = "${var.clusters["nprd-apps"].ip_subnet}.${var.clusters["nprd-apps"].ip_start_octet}/24"
  gateway     = var.clusters["nprd-apps"].gateway
  dns_servers = var.clusters["nprd-apps"].dns_servers
  domain      = var.clusters["nprd-apps"].domain
  vlan_id     = var.clusters["nprd-apps"].vlan_id

  ssh_private_key = var.ssh_private_key

  # RKE2 configuration - apps primary server
  rke2_enabled       = true
  rke2_version       = "v1.34.3+rke2r1"
  is_rke2_server     = true
  rke2_is_primary    = true
  rke2_server_token  = ""
  cluster_hostname   = var.apps_cluster_hostname
  cluster_primary_ip = var.apps_cluster_primary_ip
  cluster_aliases    = var.apps_cluster_aliases
  rke2_server_ip     = ""

  # Rancher registration - system-agent installation
  register_with_rancher        = true  # Enable system-agent for automatic Rancher registration
  rancher_hostname             = var.rancher_hostname
  rancher_ingress_ip           = var.rancher_manager_ip  # IP of Rancher ingress
  rancher_registration_token   = ""  # Will be obtained from Rancher API
  rancher_ca_checksum          = ""  # Will be obtained from Rancher API

  # CRITICAL: Only build after manager cluster AND Rancher are fully ready
  depends_on = [
    module.rke2_manager,
    module.rancher_deployment,
    proxmox_virtual_environment_download_file.ubuntu_cloud_image
  ]
}

# ============================================================================
# NPRD APPS CLUSTER - SECONDARY NODES (apps-2, apps-3)
# Only builds after apps primary is ready
# ============================================================================

module "nprd_apps_additional" {
  source = "./modules/proxmox_vm"

  for_each = {
    for i in range(1, var.clusters["nprd-apps"].node_count) :
    "nprd-apps-${i + 1}" => {
      vm_id          = var.vm_id_start_apps + i
      hostname       = "nprd-apps-${i + 1}"
      ip_address     = "${var.clusters["nprd-apps"].ip_subnet}.${var.clusters["nprd-apps"].ip_start_octet + i}/24"
      node_index     = i
    }
  }

  vm_name               = each.value.hostname
  vm_id                 = each.value.vm_id
  proxmox_node          = var.proxmox_node
  cloud_image_datastore = proxmox_virtual_environment_download_file.ubuntu_cloud_image.datastore_id
  cloud_image_file_name = proxmox_virtual_environment_download_file.ubuntu_cloud_image.file_name
  datastore_id          = var.clusters["nprd-apps"].storage

  cpu_cores    = var.clusters["nprd-apps"].cpu_cores
  memory_mb    = var.clusters["nprd-apps"].memory_mb
  disk_size_gb = var.clusters["nprd-apps"].disk_size_gb

  hostname    = each.value.hostname
  ip_address  = each.value.ip_address
  gateway     = var.clusters["nprd-apps"].gateway
  dns_servers = var.clusters["nprd-apps"].dns_servers
  domain      = var.clusters["nprd-apps"].domain
  vlan_id     = var.clusters["nprd-apps"].vlan_id

  ssh_private_key = var.ssh_private_key

  # RKE2 configuration - apps secondary servers
  rke2_enabled       = true
  rke2_version       = "v1.34.3+rke2r1"
  is_rke2_server     = true
  rke2_is_primary    = false
  rke2_server_token  = try(trimspace(data.local_file.nprd_apps_token[0].content), "")  # Token fetched locally from nprd-apps primary
  rke2_server_ip     = local.nprd_apps_primary_ip
  cluster_hostname   = var.apps_cluster_hostname
  cluster_primary_ip = var.apps_cluster_primary_ip
  cluster_aliases    = var.apps_cluster_aliases

  # Rancher registration - system-agent installation
  register_with_rancher        = true  # Enable system-agent for automatic Rancher registration
  rancher_hostname             = var.rancher_hostname
  rancher_ingress_ip           = var.rancher_manager_ip  # IP of Rancher ingress
  rancher_registration_token   = ""  # Will be obtained from Rancher API
  rancher_ca_checksum          = ""  # Will be obtained from Rancher API

  depends_on = [
    module.nprd_apps_primary,
    data.local_file.nprd_apps_token
  ]
}

# ============================================================================
# RANCHER DEPLOYMENT - ON MANAGER CLUSTER ONLY
# Installs cert-manager and Rancher via Helm after manager cluster is ready
# Must complete before apps cluster deployment so it can register with Rancher
# ============================================================================

module "rancher_deployment" {
  source = "./modules/rancher_cluster"

  cluster_name         = "rancher-manager"
  node_count           = 3
  kubeconfig_path      = module.rke2_manager.kubeconfig_path
  install_rancher      = var.install_rancher
  rancher_version      = var.rancher_version
  rancher_hostname     = var.rancher_hostname
  rancher_password     = var.rancher_password
  cert_manager_version = var.cert_manager_version

  depends_on = [
    module.rke2_manager
  ]
}

# ============================================================================
# CLEANUP GENERATED TOKENS AND VALUES ON DESTROY
# ============================================================================

resource "null_resource" "cleanup_tokens_on_destroy" {
  count = var.install_rancher ? 1 : 0

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command = <<-EOT
      CONFIG_DIR="${path.root}/../config"
      echo "Cleaning up generated Rancher tokens and configs..."
      
      # Remove Rancher API token
      if [ -f "$${CONFIG_DIR}/.rancher-api-token" ]; then
        rm -f "$${CONFIG_DIR}/.rancher-api-token"
        echo "  ✓ Removed: $${CONFIG_DIR}/.rancher-api-token"
      fi
      
      # Note: Individual kubeconfig files (~/.kube/rancher-manager.yaml, nprd-apps.yaml)
      # are not removed - they are merged into ~/.kube/config which user may want to keep
      # To fully reset, manually: rm ~/.kube/rancher-manager.yaml ~/.kube/nprd-apps.yaml
      
      echo "✓ Cleanup complete"
      echo "Note: Kubeconfig entries are merged into ~/.kube/config (not removed)"
      echo "To reset: rm ~/.kube/rancher-manager.yaml ~/.kube/nprd-apps.yaml"
    EOT
  }

  depends_on = [
    module.rancher_deployment
  ]
}

# ============================================================================
# DOWNSTREAM CLUSTER REGISTRATION - MANIFEST-BASED APPROACH
# Uses manifestUrl endpoint for reliable, self-contained registration
# ============================================================================

# The registration manifest includes all necessary RBAC, ServiceAccount,
# Deployment, and ConfigMaps for cattle-cluster-agent pods to connect
# to and register with Rancher Manager.
#
# This approach is more reliable than system-agent-install.sh because it:
# - Uses public Rancher API endpoints (manifestUrl)
# - Provides self-contained Kubernetes manifests
# - Requires only kubectl apply, not external script downloads
# - Automatically includes proper CA certificate configuration

# ============================================================================
# NPRD APPS CLUSTER - VERIFICATION
# Waits for all apps nodes to be ready
# Only starts after Rancher is deployed on manager cluster
# ============================================================================

module "rke2_apps" {
  source = "./modules/rke2_downstream_cluster"

  cluster_name         = "nprd-apps"
  cluster_hostname     = var.apps_cluster_hostname  # Use FQDN instead of IP
  agent_ips            = concat(
    [split("/", module.nprd_apps_primary.ip_address)[0]],
    [for node in module.nprd_apps_additional : split("/", node.ip_address)[0]]
  )
  ssh_private_key_path = var.ssh_private_key
  ssh_user             = "ubuntu"

  depends_on = [
    module.nprd_apps_primary,
    module.nprd_apps_additional,
    module.rancher_deployment  # Wait for Rancher to be deployed first
  ]
}

# ============================================================================
# CREATE DOWNSTREAM CLUSTER OBJECT IN RANCHER
# Creates the cluster in Rancher to generate the cluster ID
# ============================================================================

resource "null_resource" "create_downstream_cluster" {
  count = var.register_downstream_cluster ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Creating downstream cluster object in Rancher..."
      
      # Read API token from file
      API_TOKEN=$(cat "${path.root}/../config/.rancher-api-token")
      
      if [ -z "$${API_TOKEN}" ]; then
        echo "ERROR: API token file not found at ${path.root}/../config/.rancher-api-token"
        exit 1
      fi
      
      # Check if cluster already exists
      EXISTING=$(curl -sk \
        -H "Authorization: Bearer $${API_TOKEN}" \
        "https://${var.rancher_hostname}/v3/clusters" \
        | grep -o '"name":"${local.downstream_cluster_name}"' || echo "")
      
      if [ -n "$${EXISTING}" ]; then
        echo "  ✓ Cluster '${local.downstream_cluster_name}' already exists in Rancher"
      else
        echo "  Creating cluster '${local.downstream_cluster_name}'..."
        curl -sk \
          -X POST \
          -H "Authorization: Bearer $${API_TOKEN}" \
          -H "Content-Type: application/json" \
          -d '{"name":"${local.downstream_cluster_name}","description":"Non-production applications cluster"}' \
          "https://${var.rancher_hostname}/v3/clusters" > /dev/null
        echo "  ✓ Cluster created successfully"
      fi
    EOT
  }

  depends_on = [
    module.rancher_deployment,
    null_resource.fetch_manager_token
  ]
}

# ============================================================================
# FETCH DOWNSTREAM CLUSTER ID FROM RANCHER API
# Extracts the cluster ID after cluster object is created
# ============================================================================

locals {
  cluster_id_file = "${abspath("${path.root}/../config")}/.downstream-cluster-id"
}

resource "null_resource" "fetch_downstream_cluster_id" {
  count = var.register_downstream_cluster ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Fetching downstream cluster ID from Rancher API..."
      
      # Read API token from file
      API_TOKEN=$(cat "${path.root}/../config/.rancher-api-token")
      
      if [ -z "$${API_TOKEN}" ]; then
        echo "ERROR: API token file not found at ${path.root}/../config/.rancher-api-token"
        exit 1
      fi
      
      # Query Rancher API for the downstream cluster specifically (using jq for reliable JSON parsing)
      CLUSTER_ID=$(curl -sk \
        -H "Authorization: Bearer $${API_TOKEN}" \
        "https://${var.rancher_hostname}/v3/clusters" \
        | jq -r '.data[] | select(.name=="${local.downstream_cluster_name}") | .id' 2>/dev/null || echo "")
      
      if [ -z "$${CLUSTER_ID}" ]; then
        echo "ERROR: Could not fetch downstream cluster ID from Rancher API"
        echo "Ensure cluster '${local.downstream_cluster_name}' exists in Rancher Manager and API token is valid"
        exit 1
      fi
      
      echo "  ✓ Found downstream cluster ID: $${CLUSTER_ID}"
      echo "$${CLUSTER_ID}" > "${abspath("${path.root}/../config")}/.downstream-cluster-id"
    EOT
  }
  
  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "rm -f \"${abspath("${path.root}/../config")}/.downstream-cluster-id\""
  }

  depends_on = [
    null_resource.create_downstream_cluster
  ]
}

# Read the cluster ID from file
data "local_file" "downstream_cluster_id" {
  count    = var.register_downstream_cluster ? 1 : 0
  filename = local.cluster_id_file
  
  depends_on = [
    null_resource.fetch_downstream_cluster_id
  ]
}

# ============================================================================
# DOWNSTREAM CLUSTER REGISTRATION WITH RANCHER
# Applies cluster registration manifest to all nodes
# ============================================================================

module "rancher_downstream_registration" {
  count = var.register_downstream_cluster ? 1 : 0
  
  source = "./modules/rancher_downstream_registration"
  
  rancher_url            = "https://${var.rancher_hostname}"
  rancher_token_file     = "/home/lee/git/rancher-deploy/config/.rancher-api-token"
  cluster_id             = trimspace(data.local_file.downstream_cluster_id[0].content)
  ssh_private_key_path   = var.ssh_private_key
  ssh_user               = "ubuntu"
  kubeconfig_path        = "~/.kube/nprd-apps.yaml"
  
  # Map of node names to IPs for NPRD apps cluster
  cluster_nodes = {
    "nprd-apps-1" = "192.168.14.110"
    "nprd-apps-2" = "192.168.14.111"
    "nprd-apps-3" = "192.168.14.112"
  }
  
  depends_on = [
    module.rke2_apps,
    module.rancher_deployment
  ]
}

# ============================================================================
# LEGACY: INSTALL SYSTEM-AGENT ON DOWNSTREAM CLUSTER NODES (DEPRECATED)
# Deprecated in favor of manifest-based registration
# Kept for reference but not used in production deployments
# ============================================================================

# NOTE: The old system_agent_install module approach had limitations:
# - Relied on /v3/connect/agent endpoint which doesn't respond from external nodes
# - Required downloading and executing RKE2's system-agent-install.sh script
# - Timeouts and connection issues on networks with strict egress controls
# 
# The new manifestUrl approach (above) is recommended:
# - Simpler: Just applies a Kubernetes manifest via kubectl
# - More reliable: Uses public Rancher API endpoints
# - Self-contained: Manifest includes all RBAC, Deployment, ConfigMaps
# - No external downloads needed beyond curl and kubectl

# module "system_agent_install" {
#   count = false  # DISABLED - use rancher_downstream_registration instead
#   
#   source = "./modules/system_agent_install"
#   
#   rancher_url            = "https://${var.rancher_hostname}"
#   rancher_token_file     = "/home/lee/git/rancher-deploy/config/.rancher-api-token"
#   cluster_id             = "c-7c2vb"
#   install_script_path    = "${path.module}/../scripts/install-system-agent.sh"
#   ssh_private_key_path   = var.ssh_private_key
#   ssh_user               = "ubuntu"
#   
#   cluster_nodes = {
#     "nprd-apps-1" = "192.168.14.110"
#     "nprd-apps-2" = "192.168.14.111"
#     "nprd-apps-3" = "192.168.14.112"
#   }
#   
#   depends_on = [
#     null_resource.register_nprd_cluster,
#     module.rke2_apps
#   ]
# }

# ============================================================================
# MERGE ALL KUBECONFIGS TO DEFAULT LOCATION
# Merges manager and apps cluster kubeconfigs into ~/.kube/config
# ============================================================================

resource "null_resource" "merge_kubeconfigs" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "Merging all kubeconfigs to ~/.kube/config"
      echo "=========================================="
      
      mkdir -p ~/.kube
      MANAGER_CONFIG="~/.kube/rancher-manager.yaml"
      APPS_CONFIG="~/.kube/nprd-apps.yaml"
      
      # Merge manager and apps kubeconfigs into default config
      if [ -f "$${MANAGER_CONFIG}" ] && [ -f "$${APPS_CONFIG}" ]; then
        echo "Merging manager and apps kubeconfigs..."
        KUBECONFIG="~/.kube/config:$${MANAGER_CONFIG}:$${APPS_CONFIG}" kubectl config view --flatten > ~/.kube/config.tmp
        mv ~/.kube/config.tmp ~/.kube/config
        chmod 600 ~/.kube/config
        echo "✓ Merged both kubeconfigs to ~/.kube/config"
      elif [ -f "$${MANAGER_CONFIG}" ]; then
        echo "Merging manager kubeconfig (apps not yet available)..."
        KUBECONFIG="~/.kube/config:$${MANAGER_CONFIG}" kubectl config view --flatten > ~/.kube/config.tmp
        mv ~/.kube/config.tmp ~/.kube/config
        chmod 600 ~/.kube/config
        echo "✓ Merged manager kubeconfig to ~/.kube/config"
      fi
      
      # Rename contexts to meaningful names
      kubectl config rename-context "rancher-manager" "rancher-manager" 2>/dev/null || true
      kubectl config rename-context "nprd-apps" "nprd-apps" 2>/dev/null || true
      
      echo ""
      echo "Available contexts:"
      kubectl config get-contexts --no-headers 2>/dev/null | sed 's/^/  /'
      echo ""
      echo "To switch clusters:"
      echo "  kubectl config use-context rancher-manager"
      echo "  kubectl config use-context nprd-apps"
      echo ""
      echo "Or use kubectx (if installed):"
      echo "  kubectx                    # List contexts"
      echo "  kubectx rancher-manager    # Switch to manager"
      echo "  kubectx nprd-apps          # Switch to apps"
    EOT
  }

  depends_on = [
    module.rancher_downstream_registration
  ]
}

