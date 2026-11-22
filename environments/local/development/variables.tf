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

variable "tailscale_suffix" {
  # Populated from the TF_VAR_tailscale_suffix environment variable (MagicDNS tailnet suffix, e.g. my-tailnet.ts.net)
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