# RKE2 cluster on KVM — local development backend & provider configuration.
# Only the `key` differs across environments (dev/staging/prod).

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
    key    = "local/development/terraform.tfstate"
    region = "us-east-1"

    # Floci endpoint on the Proxmox VM (same emulator the AWS provider wiring uses).
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
    # S3-native state locking (needs Terraform >= 1.10). Replaces the old
    # `dynamodb_table` mechanism; the two are mutually exclusive.
    use_lockfile = true
  }
}

provider "libvirt" {
}