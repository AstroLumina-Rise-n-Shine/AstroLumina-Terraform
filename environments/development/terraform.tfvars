# Development values: the small cluster. One environment runs at a time
# on the laptop (see "One environment at a time" in the repo README).
ssh_pub_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQIgh+H2AXLQyqOm5uVT0r0FhT9iAnF6k9d7UjrxUh5 daniel.catalin.pirvu@gmail.com"
ssh_password = "ubuntu"

cp_vcpu      = 2
cp_memory_mb = 3072
cp_disk_gb   = 30

worker_vcpu      = 2
worker_memory_mb = 2048
worker_disk_gb   = 30

# Labeling: stamped on every VM at /etc/astrolumina-environment.
environment = "development"
