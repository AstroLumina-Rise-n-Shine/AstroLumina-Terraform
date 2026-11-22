# RKE2 cluster on KVM — local development module calls only.
# All provider/backend config is in backend.tf
# All variable definitions are in variables.tf
# All variable values are in variables.tfvars
# All outputs are in outputs.tf

locals {
  # Ubuntu base image path (dynamic based on ubuntu_version variable)
  ubuntu_image_path = "/var/lib/libvirt/images/ubuntu-${var.ubuntu_version}.qcow2"
  k8s_share_path    = var.k8s_repo_host_path != null ? var.k8s_repo_host_path : abspath("${path.module}/../../../AstroLumina-Kubernetes")
}

# ============================================================
# Module calls — libvirt path via modules/libvirt_vm
# ============================================================
module "rke2_cp_01" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/libvirt_vm?ref=1.0.8"

  vm_name            = "rke2-lbvrt-cp-01"
  vcpu               = var.cp_vcpu
  memory_mb          = var.cp_memory_mb
  disk_gb            = var.cp_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key
  # Static IP via cloud-init (no MAC dependency)
  ipv4_address = "${var.ip_cp}/${var.lan_prefix}"
  ipv4_gateway = var.lan_gateway
  nameservers  = var.nameservers

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "local"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

module "rke2_wk_01" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/libvirt_vm?ref=1.0.8"

  vm_name            = "rke2-lbvrt-wk-01"
  vcpu               = var.worker_vcpu
  memory_mb          = var.worker_memory_mb
  disk_gb            = var.worker_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key
  # Static IP via cloud-init (no MAC dependency)
  ipv4_address = "${var.ip_w1}/${var.lan_prefix}"
  ipv4_gateway = var.lan_gateway
  nameservers  = var.nameservers

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "local"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

module "rke2_wk_02" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/libvirt_vm?ref=1.0.8"

  vm_name            = "rke2-lbvrt-wk-02"
  vcpu               = var.worker_vcpu
  memory_mb          = var.worker_memory_mb
  disk_gb            = var.worker_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key
  # Static IP via cloud-init (no MAC dependency)
  ipv4_address = "${var.ip_w2}/${var.lan_prefix}"
  ipv4_gateway = var.lan_gateway
  nameservers  = var.nameservers

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "local"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}