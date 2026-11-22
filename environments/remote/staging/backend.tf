# RKE2 cluster on Proxmox (QM) — remote development backend & provider configuration.
# Only the `key` differs across environments (dev/staging/prod).

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = ">= 2.9.14"
    }
  }

  backend "s3" {
    bucket       = "astrolumina-terraform-state"
    key          = "remote/staging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true

    endpoints = {
      s3       = "http://192.168.100.50:4566"
      dynamodb = "http://192.168.100.50:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

provider "proxmox" {
  # Credentials come from environment variables at runtime, not hardcoded:
  #   PM_API_URL       -> e.g. https://192.168.100.200:8006/
  #   PM_USER          -> root@pam
  #   PM_PASSWD        -> PVE account password
  #   PM_OTP           -> OTP token (optional, for 2FA)
  #
  # tf.sh sets them automatically when invoking terraform for remote.
  pm_api_url      = var.pm_api_url
  pm_tls_insecure = true
  # Maximum timeout for long-running operations (VM creation + cloud-init).
  pm_timeout = 600
}