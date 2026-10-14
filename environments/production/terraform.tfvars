# Production values: the large cluster. One environment runs at a time
# on the laptop -- do not apply while another environment is live.
ssh_pub_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQIgh+H2AXLQyqOm5uVT0r0FhT9iAnF6k9d7UjrxUh5 daniel.catalin.pirvu@gmail.com"
ssh_password = "ubuntu"

cp_vcpu      = 2
cp_memory_mb = 6144
cp_disk_gb   = 50

worker_vcpu      = 2
worker_memory_mb = 4096
worker_disk_gb   = 50

# Labeling: stamped on every VM at /etc/astrolumina-environment.
environment = "production"
