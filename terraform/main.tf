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
  manager_token_file = "${path.module}/.manager-token"
}

resource "null_resource" "fetch_manager_token" {
  provisioner "local-exec" {
    command = "bash ${path.module}/fetch-token.sh ${var.ssh_private_key} ${local.manager_primary_ip} ${local.manager_token_file}"
  }

  # Clean up token file on destroy
  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "rm -f ${path.module}/.manager-token"
  }

  depends_on = [
    module.rancher_manager_primary
  ]
}

# Read the token back from file
data "local_file" "manager_token" {
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
  rke2_server_token  = trimspace(data.local_file.manager_token.content)  # Token fetched locally from primary
  rke2_server_ip     = local.manager_primary_ip  # Primary IP

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
  apps_primary_ip = split("/", module.nprd_apps_primary.ip_address)[0]
  apps_token_file = "${path.module}/.apps-token"
}

resource "null_resource" "fetch_apps_token" {
  provisioner "local-exec" {
    command = "bash ${path.module}/fetch-token.sh ${var.ssh_private_key} ${local.apps_primary_ip} ${local.apps_token_file}"
  }

  depends_on = [
    module.nprd_apps_primary
  ]
}

# Read the apps token back from file
data "local_file" "apps_token" {
  filename = local.apps_token_file
  depends_on = [
    null_resource.fetch_apps_token
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
  rke2_server_ip     = ""

  # CRITICAL: Only build after manager cluster is fully ready
  depends_on = [
    module.rke2_manager,
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
  rke2_server_token  = trimspace(data.local_file.apps_token.content)  # Token fetched locally from apps primary
  rke2_server_ip     = local.apps_primary_ip

  depends_on = [
    module.nprd_apps_primary,
    data.local_file.apps_token
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
# DOWNSTREAM CLUSTER REGISTRATION - NATIVE RANCHER PROVIDER
# Uses rancher2_cluster resource with API token created by deploy-rancher.sh
# ============================================================================

resource "rancher2_cluster" "nprd_apps" {
  count = var.register_downstream_cluster ? 1 : 0

  name                            = "nprd-apps"
  description                     = "Non-production applications cluster deployed via Terraform"
  enable_cluster_monitoring       = true

  depends_on = [
    module.rancher_deployment,
    module.rke2_apps
  ]
}

# ============================================================================
# NPRD APPS CLUSTER - VERIFICATION
# Waits for all apps nodes to be ready
# Only starts after Rancher is deployed on manager cluster
# ============================================================================

module "rke2_apps" {
  source = "./modules/rke2_downstream_cluster"

  cluster_name         = "nprd-apps"
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

