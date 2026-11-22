# RKE2 cluster on KVM — local development outputs.
# Same output names as the old single-root layout for backward compatibility.

output "vm_ips" {
  description = "VM IP addresses"
  value = {
    control_plane = module.rke2_cp_01.ip_address
    worker_1      = module.rke2_wk_01.ip_address
    worker_2      = module.rke2_wk_02.ip_address
  }
}

output "vm_details" {
  description = "VM details"
  value = [
    {
      name        = module.rke2_cp_01.vm_name
      vcpu        = module.rke2_cp_01.vcpu
      memory_mb   = module.rke2_cp_01.memory_mb
      disk_gb     = module.rke2_cp_01.disk_gb
      role        = "control-plane"
      environment = var.environment
    },
    {
      name        = module.rke2_wk_01.vm_name
      vcpu        = module.rke2_wk_01.vcpu
      memory_mb   = module.rke2_wk_01.memory_mb
      disk_gb     = module.rke2_wk_01.disk_gb
      role        = "worker"
      environment = var.environment
    },
    {
      name        = module.rke2_wk_02.vm_name
      vcpu        = module.rke2_wk_02.vcpu
      memory_mb   = module.rke2_wk_02.memory_mb
      disk_gb     = module.rke2_wk_02.disk_gb
      role        = "worker"
      environment = var.environment
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
  # Stable MagicDNS names (survive VM rebuilds as long as vm_name is unchanged); null when tailscale_suffix is not set
  description = "Stable Tailscale MagicDNS hostnames for SSH access"
  value = var.tailscale_suffix != "" ? {
    control_plane = "${module.rke2_cp_01.vm_name}.${var.tailscale_suffix}"
    worker_1      = "${module.rke2_wk_01.vm_name}.${var.tailscale_suffix}"
    worker_2      = "${module.rke2_wk_02.vm_name}.${var.tailscale_suffix}"
  } : null
}