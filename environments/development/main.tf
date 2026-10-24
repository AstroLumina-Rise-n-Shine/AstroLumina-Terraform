# RKE2 cluster on KVM: thin environment root.
#
# This file is intentionally identical across development / staging /
# production -- ONLY the backend `key` below and terraform.tfvars next to
# it differ. Shared logic
# lives in the AstroLumina-Terraform-Library `kvm_vm` module; each
# environment gets its own state file, so apply/destroy here never touches
# the other two. Rule of the lab: a single laptop runs ONE environment at
# a time (destroy the current one before applying another).

terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }

  # Remote state in Floci-emulated S3 with S3-native locking (a `.tflock`
  # object next to each state key, via conditional writes -- no DynamoDB).
  # Keep this block IDENTICAL across environments except `key`: one state
  # object + one lock object per environment.
  backend "s3" {
    bucket = "astrolumina-terraform-state"
    key    = "development/terraform.tfstate"
    region = "us-east-1"

    # Floci local endpoint (same emulator the AWS provider wiring uses).
    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
    # S3-native state locking (needs Terraform >= 1.10). Replaces the old
    # `dynamodb_table` mechanism; the two are mutually exclusive.
    use_lockfile = true
  }
}

provider "libvirt" {
}

# ============================================================
# Variables (values come from terraform.tfvars)
# ============================================================
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
  description = "Environment name for labeling (development, staging or production). Passed into every VM module call and stamped on the guest at /etc/astrolumina-environment -- set per env in terraform.tfvars."
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

locals {
  # Names, MACs and LAN IPs are identical in every environment on purpose:
  # tf.sh, the Tailscale hostnames and the Kubernetes node names all rely
  # on them, and a single laptop runs one environment at a time anyway.
  # Only sizing differs per environment (see terraform.tfvars).
  ubuntu_image_path = "/var/lib/libvirt/images/ubuntu-24.04.qcow2"
  k8s_share_path    = var.k8s_repo_host_path != null ? var.k8s_repo_host_path : abspath("${path.module}/../../../AstroLumina-Kubernetes")
}

# ============================================================
module "rke2_control_plane" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/kvm_vm?ref=1.0.5"

  vm_name            = "rke2-cp-01"
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
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

module "rke2_worker_01" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/kvm_vm?ref=1.0.5"

  vm_name            = "rke2-worker-01"
  vcpu               = var.worker_vcpu
  memory_mb          = var.worker_memory_mb
  disk_gb            = var.worker_disk_gb
  ssh_username       = "ubuntu"
  ssh_pub_key        = var.ssh_pub_key
  ssh_password       = var.ssh_password
  tailscale_auth_key = var.tailscale_auth_key
  mac_address        = "52:54:00:d1:e2:f3"

  # This node answers *.k8s.astrolumina.ro with its own Tailscale IP (split DNS)
  tailnet_dns_zone = "k8s.astrolumina.ro"

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

module "rke2_worker_02" {
  source = "git::https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library.git//modules/kvm_vm?ref=1.0.5"

  vm_name            = "rke2-worker-02"
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
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  environment = var.environment

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

# ============================================================
# Outputs (same names as the old single-root layout)
# ============================================================
output "vm_ips" {
  description = "VM IP addresses"
  value = {
    control_plane = module.rke2_control_plane.ip_address
    worker_1      = module.rke2_worker_01.ip_address
    worker_2      = module.rke2_worker_02.ip_address
  }
}

output "vm_details" {
  description = "VM details"
  value = [
    {
      name        = module.rke2_control_plane.vm_name
      vcpu        = module.rke2_control_plane.vcpu
      memory_mb   = module.rke2_control_plane.memory_mb
      disk_gb     = module.rke2_control_plane.disk_gb
      role        = "control-plane"
      environment = var.environment
    },
    {
      name        = module.rke2_worker_01.vm_name
      vcpu        = module.rke2_worker_01.vcpu
      memory_mb   = module.rke2_worker_01.memory_mb
      disk_gb     = module.rke2_worker_01.disk_gb
      role        = "worker"
      environment = var.environment
    },
    {
      name        = module.rke2_worker_02.vm_name
      vcpu        = module.rke2_worker_02.vcpu
      memory_mb   = module.rke2_worker_02.memory_mb
      disk_gb     = module.rke2_worker_02.disk_gb
      role        = "worker"
      environment = var.environment
    }
  ]
}

output "ssh_connection_info" {
  description = "How to connect over SSH"
  value = [
    "ssh ubuntu@${module.rke2_control_plane.ip_address}",
    "ssh ubuntu@${module.rke2_worker_01.ip_address}",
    "ssh ubuntu@${module.rke2_worker_02.ip_address}"
  ]
}

output "tailscale_hostnames" {
  # Stable MagicDNS names (survive VM rebuilds as long as vm_name is unchanged); null when tailscale_suffix is not set
  description = "Stable Tailscale MagicDNS hostnames for SSH access"
  value = var.tailscale_suffix != "" ? {
    control_plane = "${module.rke2_control_plane.vm_name}.${var.tailscale_suffix}"
    worker_1      = "${module.rke2_worker_01.vm_name}.${var.tailscale_suffix}"
    worker_2      = "${module.rke2_worker_02.vm_name}.${var.tailscale_suffix}"
  } : null
}
