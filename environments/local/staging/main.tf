# RKE2 cluster on KVM — local development module calls only.
# All provider/backend config is in backend.tf
# All variable definitions are in variables.tf
# All variable values are in variables.tfvars
# All outputs are in outputs.tf

locals {
  # Names, MACs and LAN IPs are identical in every environment on purpose:
  # tf.sh, the Tailscale hostnames and the Kubernetes node names all rely
  # on them, and a single laptop runs one environment at a time anyway.
  # Only sizing differs per environment (see variables.tfvars).
  ubuntu_image_path = "/var/lib/libvirt/images/ubuntu-24.04.qcow2"
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
  mac_address        = "52:54:00:a1:b2:c3"

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
  mac_address        = "52:54:00:d1:e2:f3"


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
  mac_address        = "52:54:00:aa:bb:cc"

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