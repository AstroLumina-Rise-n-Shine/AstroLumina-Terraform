# RKE2 cluster on Proxmox (QM) — remote development variable definitions.
# Values are set in variables.tfvars (one per environment).

variable "ssh_pub_key" {
  description = "SSH public key for access"
  type        = string
}

variable "ssh_password" {
  description = "Password for user ubuntu (plain text - hashed by cloud-init)"
  type        = string
  default     = "ubuntu"
}

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key (empty disables Tailscale setup)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_dns" {
  description = "Tailscale MagicDNS suffix"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment label stamped on every VM (/etc/astrolumina-environment)"
  type        = string
}

variable "cp_vcpu" {
  description = "Control-plane vCPU count"
  type        = number
  default     = 2
}

variable "cp_memory_mb" {
  description = "Control-plane RAM in MB"
  type        = number
  default     = 3072
}

variable "cp_disk_gb" {
  description = "Control-plane disk in GB"
  type        = number
  default     = 30
}

variable "worker_vcpu" {
  description = "Worker vCPU count (both workers)"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "Worker RAM in MB (both workers)"
  type        = number
  default     = 4096
}

variable "worker_disk_gb" {
  description = "Worker disk in GB (both workers)"
  type        = number
  default     = 30
}

# -------------------------------------------------------
# Proxmox infrastructure pointers (override in tfvars per-env if needed)
# -------------------------------------------------------
variable "pm_api_url" {
  description = "Proxmox VE API endpoint"
  type        = string
  default     = "https://192.168.100.200:8006/"
}

variable "pm_node" {
  description = "Proxmox node name where VMs land"
  type        = string
  default     = "pve"
}

variable "pm_storage" {
  description = "Storage pool used for disks and cloud-init disk"
  type        = string
  default     = "local"
}

variable "pm_network_bridge" {
  description = "Linux bridge for the primary NIC"
  type        = string
  default     = "vmbr0"
}

variable "pm_ssh_user" {
  description = "SSH user on the Proxmox node (for uploading cloud-init snippet via null_resource)"
  type        = string
  default     = "root"
}

variable "pm_password" {
  description = "Password for the Proxmox SSH user (for null_resource file upload). Optional if using SSH keys."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pm_template" {
  description = "Name of the cloud-init ready VM template to clone (must exist on the Proxmox node)"
  type        = string
  default     = "ubuntu-24.04-cloudinit-template"
}

# Ubuntu version for base image / template (24.04 or 26.04)
variable "ubuntu_version" {
  description = "Ubuntu LTS version for base image / template (24.04 or 26.04)"
  type        = string
  default     = "24.04"
  validation {
    condition     = contains(["24.04", "26.04"], var.ubuntu_version)
    error_message = "ubuntu_version must be '24.04' or '26.04'."
  }
}