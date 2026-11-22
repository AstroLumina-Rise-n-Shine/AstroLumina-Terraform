# Staging values: same sizing as development, different label.
ssh_pub_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQIgh+H2AXLQyqOm5uVT0r0FhT9iAnF6k9d7UjrxUh5 AstroLumina Admin"
ssh_password = "ubuntu"

cp_vcpu      = 2
cp_memory_mb = 3072
cp_disk_gb   = 30

worker_vcpu      = 2
worker_memory_mb = 4096
worker_disk_gb   = 30

# Labeling: stamped on every VM at /etc/astrolumina-environment.
environment   = "local-staging"
tailscale_dns = "tarpan-mimosa.ts.net"

# ============================================================
# Network configuration (static IPs via cloud-init)
# ============================================================
lan_prefix  = 24
lan_gateway = "192.168.200.1"
nameservers = "1.1.1.1,8.8.8.8"

ip_cp = "192.168.200.210"
ip_w1 = "192.168.200.211"
ip_w2 = "192.168.200.212"

# Ubuntu version for base image (24.04 or 26.04)
ubuntu_version = "24.04"