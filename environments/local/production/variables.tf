# RKE2 cluster on KVM — local development variable definitions.
# Values are set in variables.tfvars (one per environment).

variable "ssh_pub_key" {
  description = "SSH public key for access"
  type        = string
}

variable "ssh_password" {
  description = "Password for user ubuntu (plain text - will be hashed by cloud-init)"
  type        = string
  default     = "ubuntu"
}

variable "k8s_repo_host_path" {
  description = "Host path of AstroLumina-Kubernetes shared read-only into all VMs via 9p (null = sibling repo, empty disables sharing)"
  type        = string
  default     = null
}

variable "tailscale_auth_key" {
  # Populated from the TF_VAR_tailscale_auth_key environment variable (reusable + ephemeral key from the Tailscale admin console)
  description = "Tailscale reusable auth key for automatic tailnet enrollment (empty string disables Tailscale setup)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_dns" {
  # Populated from the TF_VAR_tailscale_dns environment variable (MagicDNS tailnet suffix, e.g. my-tailnet.ts.net)
  description = "Tailscale MagicDNS suffix used to build stable VM hostnames (empty string disables MagicDNS outputs)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name for labeling (development, staging or production). Passed into every VM module call and stamped on the guest at /etc/astrolumina-environment -- set per env in variables.tfvars."
  type        = string
}

variable "cp_vcpu" {
  description = "Control-plane virtual CPUs"
  type        = number
}

variable "cp_memory_mb" {
  description = "Control-plane RAM in MB"
  type        = number
}

variable "cp_disk_gb" {
  description = "Control-plane OS disk in GB"
  type        = number
}

variable "worker_vcpu" {
  description = "Worker virtual CPUs (both workers)"
  type        = number
}

variable "worker_memory_mb" {
  description = "Worker RAM in MB (both workers)"
  type        = number
}

variable "worker_disk_gb" {
  description = "Worker OS disk in GB (both workers)"
  type        = number
}

# ============================================================
# Network configuration (moved from locals to variables)
# ============================================================
variable "lan_prefix" {
  description = "LAN subnet prefix length (e.g., 24 for /24)"
  type        = number
  default     = 24
}

variable "lan_gateway" {
  description = "LAN gateway IP address"
  type        = string
  default     = "192.168.200.1"
}

variable "nameservers" {
  description = "Comma-separated DNS nameservers for cloud-init"
  type        = string
  default     = "1.1.1.1,8.8.8.8"
}

variable "ip_cp" {
  description = "Control-plane static IP address (no CIDR suffix)"
  type        = string
  default     = "192.168.200.210"
}

variable "ip_w1" {
  description = "Worker-1 static IP address (no CIDR suffix)"
  type        = string
  default     = "192.168.200.211"
}

variable "ip_w2" {
  description = "Worker-2 static IP address (no CIDR suffix)"
  type        = string
  default     = "192.168.200.212"
}

# Ubuntu version for base image (24.04 or 26.04)
variable "ubuntu_version" {
  description = "Ubuntu LTS version for base image (24.04 or 26.04)"
  type        = string
  default     = "24.04"
  validation {
    condition     = contains(["24.04", "26.04"], var.ubuntu_version)
    error_message = "ubuntu_version must be '24.04' or '26.04'."
  }
}