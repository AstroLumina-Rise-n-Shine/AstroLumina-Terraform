# RKE2 cluster on Proxmox (QM) — remote development outputs.

output "vm_ips" {
  description = "VM IP addresses (static, set via cloud-init)"
  value = {
    control_plane = module.rke2_cp_01.ip_address
    worker_1      = module.rke2_wk_01.ip_address
    worker_2      = module.rke2_wk_02.ip_address
  }
}

output "vm_details" {
  description = "VM details summary"
  value = [
    {
      name        = module.rke2_cp_01.vm_name
      vcpu        = module.rke2_cp_01.vcpu
      memory_mb   = module.rke2_cp_01.memory_mb
      disk_gb     = module.rke2_cp_01.disk_gb
      role        = "control-plane"
      environment = var.environment
      platform    = "proxmox"
    },
    {
      name        = module.rke2_wk_01.vm_name
      vcpu        = module.rke2_wk_01.vcpu
      memory_mb   = module.rke2_wk_01.memory_mb
      disk_gb     = module.rke2_wk_01.disk_gb
      role        = "worker"
      environment = var.environment
      platform    = "proxmox"
    },
    {
      name        = module.rke2_wk_02.vm_name
      vcpu        = module.rke2_wk_02.vcpu
      memory_mb   = module.rke2_wk_02.memory_mb
      disk_gb     = module.rke2_wk_02.disk_gb
      role        = "worker"
      environment = var.environment
      platform    = "proxmox"
    }
  ]
}

output "ssh_connection_info" {
  description = "How to connect over SSH"
  value = [
    "ssh ubuntu@${module.rke2_cp_01.ip_address}",
    "ssh ubuntu@${module.rke2_wk_01.ip_address}",
    "ssh ubuntu@${module.rke2_wk_02.ip_address}"
  ]
}

output "tailscale_hostnames" {
  description = "Stable Tailscale MagicDNS hostnames (null when suffix not set)"
  value = var.tailscale_dns != "" ? {
    control_plane = "${module.rke2_cp_01.vm_name}.${var.tailscale_dns}"
    worker_1      = "${module.rke2_wk_01.vm_name}.${var.tailscale_dns}"
    worker_2      = "${module.rke2_wk_02.vm_name}.${var.tailscale_dns}"
  } : null
}

output "pm_node" {
  description = "Proxmox node targeted by this environment"
  value       = var.pm_node
}

output "pm_api_url" {
  description = "Proxmox API URL used"
  value       = var.pm_api_url
}