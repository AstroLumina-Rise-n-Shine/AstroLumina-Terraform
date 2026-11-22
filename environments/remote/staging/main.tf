# RKE2 cluster on Proxmox (QM) — remote development module calls only.
# All provider/backend config is in backend.tf
# All variable definitions are in variables.tf
# All variable values are in variables.tfvars
# All outputs are in outputs.tf

locals {
  # Subnet + gateway for the PVE LAN (192.168.100.0/24, gw .1).
  # These feed directly into cloud-init so the guest never needs a DHCP
  # reservation — the address is pinned at first boot.
  lan_prefix  = 24
  lan_gateway = "192.168.100.1"
  nameservers = "1.1.1.1,8.8.8.8"

  # Assigned IPs are chosen from the same /24 and match tf.sh's inventory.
  ip_cp = "192.168.100.210"
  ip_w1 = "192.168.100.211"
  ip_w2 = "192.168.100.212"
}

# ============================================================
# Module calls – QEMU/Proxmox path via modules/qm_vm
# ============================================================
module "rke2_cp_01" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/qm_vm?ref=1.0.8"

  vm_name            = "rke2-qm-cp-01"
  vcpu               = var.cp_vcpu
  memory_mb          = var.cp_memory_mb
  disk_gb            = var.cp_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key

  pm_api_url        = var.pm_api_url
  pm_node           = var.pm_node
  pm_storage        = var.pm_storage
  pm_network_bridge = var.pm_network_bridge
  pm_ssh_user       = var.pm_ssh_user
  pm_password       = var.pm_password
  pm_template       = var.pm_template

  ipv4_address = "${local.ip_cp}/${local.lan_prefix}"
  ipv4_gateway = local.lan_gateway
  nameservers  = local.nameservers

  environment = var.environment

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

module "rke2_wk_01" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/qm_vm?ref=1.0.8"

  vm_name            = "rke2-qm-wk-01"
  vcpu               = var.worker_vcpu
  memory_mb          = var.worker_memory_mb
  disk_gb            = var.worker_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key

  pm_api_url        = var.pm_api_url
  pm_node           = var.pm_node
  pm_storage        = var.pm_storage
  pm_network_bridge = var.pm_network_bridge
  pm_ssh_user       = var.pm_ssh_user
  pm_password       = var.pm_password
  pm_template       = var.pm_template

  ipv4_address = "${local.ip_w1}/${local.lan_prefix}"
  ipv4_gateway = local.lan_gateway
  nameservers  = local.nameservers

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

module "rke2_wk_02" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/qm_vm?ref=1.0.8"

  vm_name            = "rke2-qm-wk-02"
  vcpu               = var.worker_vcpu
  memory_mb          = var.worker_memory_mb
  disk_gb            = var.worker_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key

  pm_api_url        = var.pm_api_url
  pm_node           = var.pm_node
  pm_storage        = var.pm_storage
  pm_network_bridge = var.pm_network_bridge
  pm_ssh_user       = var.pm_ssh_user
  pm_password       = var.pm_password
  pm_template       = var.pm_template

  ipv4_address = "${local.ip_w2}/${local.lan_prefix}"
  ipv4_gateway = local.lan_gateway
  nameservers  = local.nameservers

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}