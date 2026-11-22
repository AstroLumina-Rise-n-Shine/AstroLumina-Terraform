# Remote (Proxmox) — production sizing.
# Note: state lives in the shared Floci bucket (key remote/production/...)
# so apply here runs against the Proxmox host API, not against libvirt.

ssh_pub_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQIgh+H2AXLQyqOm5uVT0r0FhT9iAnF6k9d7UjrxUh5 AstroLumina Admin"
ssh_password = "ubuntu"

cp_vcpu      = 2
cp_memory_mb = 3072
cp_disk_gb   = 30

worker_vcpu      = 2
worker_memory_mb = 4096
worker_disk_gb   = 30

environment      = "remote-production"
tailscale_dns = ""

# -------------------------------------------------------
# Proxmox host pointers (match your lab)
# -------------------------------------------------------
pm_api_url        = "https://192.168.100.200:8006/"
pm_node           = "danel"
pm_storage        = "local"
pm_network_bridge = "vmbr0"
pm_ssh_user       = "root"
pm_password       = "" # set via PM_PASSWORD env var in tf.sh or fill in here
pm_template       = "ubuntu-24.04-cloudinit-template"