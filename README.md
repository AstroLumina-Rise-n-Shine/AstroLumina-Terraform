# Terraform RKE2 Cluster on KVM/QEMU

Terraform infrastructure for the RKE2 Kubernetes cluster VMs (1 control
plane + 2 workers) on local KVM/QEMU.

Shared modules live in
[AstroLumina-Terraform-Library](https://github.com/AstroLumina-Rise-n-Shine/AstroLumina-Terraform-Library)
(`kvm_vm`: one libvirt VM with cloud-init) and are consumed here via
`source = "git::...//modules/kvm_vm"`. This repo holds only the
thin environment roots: identical `main.tf` files plus one
`terraform.tfvars` with values per environment.

## Structure

```
AstroLumina-Terraform/
├── environments/
│   ├── development/      # Small cluster (own state file)
│   │   ├── main.tf       # Thin root: provider + module call + outputs
│   │   └── terraform.tfvars  # Values: 2/3GB CP, 2/2GB workers
│   ├── staging/          # Original sizing (own state file)
│   │   ├── main.tf       # Byte-identical to development/main.tf
│   │   └── terraform.tfvars  # Values: 2/4GB CP, 2/3GB workers
│   └── production/       # Large cluster (own state file)
│       ├── main.tf       # Byte-identical to development/main.tf
│       └── terraform.tfvars  # Values: 2/6GB CP, 2/4GB workers
├── tf.sh                   # Helper script (init, apply, destroy, start, stop, ips)
└── configs/
    ├── network-default.xml   # libvirt network + DHCP reservations (KVM/QEMU only)
    └── ssh_config            # SSH aliases (rke2-cp-01, rke2-worker-01/02)
```

## One environment at a time

VM names, MACs and LAN IPs are **identical in every environment** on
purpose: `tf.sh`, the Tailscale hostnames and the Kubernetes node names all
rely on them. A single laptop runs **one environment at a time** — destroy
the current one before applying another:

```bash
./tf.sh destroy          # development (default)
./tf.sh staging apply    # then staging
```

`tf.sh` takes an optional leading environment name (`development` default,
or `TF_ENV`): `./tf.sh production apply`, `./tf.sh staging destroy`.

## VM Specifications

| Node           | vCPU        | RAM               | Disk            | Role                        |
| -------------- | ----------- | ----------------- | --------------- | --------------------------- |
| rke2-cp-01     | 2           | 3/4/6 GB          | 30/40/50 GB     | Control Plane (RKE2 server) |
| rke2-worker-01 | 2           | 2/3/4 GB          | 30/40/50 GB     | Worker (RKE2 agent)         |
| rke2-worker-02 | 2           | 2/3/4 GB          | 30/40/50 GB     | Worker (RKE2 agent)         |

Columns are development / staging / production (see each
`terraform.tfvars` — the only files that differ between environments).

## System Requirements (KVM/QEMU)

### Required packages

```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-system-x86 \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    terraform
```

(Terraform itself: see `01-terraform-install.md` in the Library repo.)

### KVM/QEMU check

```bash
kvm-ok
virt-host-validate
```

### AppArmor (KVM/QEMU - ZorinOS, Ubuntu, etc.)

**KVM/QEMU note:** if the system has AppArmor enabled, libvirtd will not start the VMs:

```bash
sudo systemctl stop apparmor
sudo systemctl restart libvirtd
```

### Virtual network (KVM/QEMU only)

**KVM/QEMU specific:** the virtual network and fixed IPs are configured in libvirt.

Configuration file: `configs/network-default.xml`

```bash
./tf.sh init
```

If done manually:

```bash
sudo virsh net-define configs/network-default.xml
sudo virsh net-start default
sudo virsh net-autostart default
```

### Storage Pool (KVM/QEMU only)

**KVM/QEMU specific:** KVM ships with a preconfigured `default` storage pool:

```
/var/lib/libvirt/images/
```

Base images (ubuntu.qcow2) go here and VM disks are created here. No additional configuration needed.

## Configuration

### 1. Base image initialization

The `tf.sh init` script downloads the Ubuntu 24.04 Cloud Image and converts it to QCOW2:

```bash
./tf.sh init
```

This:

- Downloads `ubuntu-24.04-server-cloudimg-amd64.img` to `/var/lib/libvirt/images/`
- Converts it to QCOW2 (the format required by libvirt)
- Sets the correct permissions
- Runs `terraform init` in `environments/development`

### 2. Terraform check

```bash
terraform -chdir=environments/development init -backend=false
terraform -chdir=environments/development validate
```

### 3. Create VMs

```bash
./tf.sh development apply   # or staging / production
```

Run it twice (the second run picks up the DHCP IPs).

### 4. Adopting the pre-split live state (one time)

The cluster built by the old single-root layout is still tracked by
`terraform.tfstate` at the repo root. The `development` environment keeps
the exact same module addresses (`module.rke2_control_plane`, ...), so
adopting the live VMs is a file copy -- no `state mv` needed:

```bash
cp terraform.tfstate* environments/development/
cd environments/development
terraform init
terraform plan   # must show no changes
```

`staging` and `production` start with fresh state files (their first
`apply` creates new VMs -- remember the one-environment-at-a-time rule).
Keep the root `terraform.tfstate*` files until the adoption is verified,
then delete them.

## Helper commands (tf.sh)

| Command                          | Description                                                              |
| -------------------------------- | ------------------------------------------------------------------------ |
| `./tf.sh [env] init`             | Downloads base images, configures the network and initializes Terraform |
| `./tf.sh [env] apply`            | Creates the VMs with fixed IPs (192.168.122.10, .11, .12)               |
| `./tf.sh [env] destroy`          | Destroys all VMs                                                        |
| `./tf.sh start`                  | Starts the VMs                                                          |
| `./tf.sh stop`                   | Gracefully stops the VMs                                                |
| `./tf.sh force-stop`             | Force-stops the VMs                                                     |
| `./tf.sh ips`                    | Shows DHCP IPs and VM status                                            |
| `./tf.sh status`                 | Shows the running VMs                                                   |

`[env]` is `development` (default), `staging` or `production`.

## Fixed IPs (KVM/QEMU only)

**KVM/QEMU specific:** the VMs get fixed IPs via DHCP reservations defined in `configs/network-default.xml`:

| VM             | MAC Address       | Fixed IP       |
| -------------- | ----------------- | -------------- |
| rke2-cp-01     | 52:54:00:a1:b2:c3 | 192.168.122.10 |
| rke2-worker-01 | 52:54:00:d1:e2:f3 | 192.168.122.11 |
| rke2-worker-02 | 52:54:00:aa:bb:cc | 192.168.122.12 |

## VM access

```bash
terraform -chdir=environments/development output ssh_connection_info
```

Or:

```bash
./tf.sh ips
```

SSH connection (see also `configs/ssh_config` aliases):

```bash
ssh ubuntu@<VM_IP>
# Password: ubuntu
```

## Kubernetes repo shared with the VMs (9p)

The `AstroLumina-Kubernetes` directory on the host is automatically shared,
read-only, with all 3 VMs via 9p filesystem passthrough. After boot,
the repo is available on any VM at:

```bash
ls /mnt/k8s/development/
kubectl apply -k /mnt/k8s/development/
```

How it works:

- Each environment root — the `k8s_repo_host_path` variable (`null` = the sibling
  `../../../AstroLumina-Kubernetes` repo, empty string = disables sharing). Can be
  overridden with `-var='k8s_repo_host_path=/other/path'` or an empty `"..."`.
- Library `modules/kvm_vm` — the `filesystems` block in `libvirt_domain` (host-side
  `mount.dir` source, `k8s_repo` tag, `passthrough`, `read_only`) +
  the `mounts` entry in cloud-init (`9p`, `trans=virtio,version=9p2000.L,ro`).
- The tag in `target.dir` must stay identical to the one in cloud-init,
  otherwise mounting fails at boot.

Host requirements (otherwise the VM fails to start or the mount is missing):

1. qemu must be able to read the path. With AppArmor stopped (see the section
   above) plus `security_driver = "none"` in `/etc/libvirt/qemu.conf`
   (lab only), nothing else is needed. With default settings,
   grant rights: `setfacl -R -m u:libvirt-qemu:rX <repo>` and `u:libvirt-qemu:--x`
   on every parent directory down to `/`.
2. The directory must exist at `terraform apply` time, otherwise libvirt refuses
   to define the domain.

Check on the VM:

```bash
mount | grep /mnt/k8s   # 9p, ro
touch /mnt/k8s/probe && echo PROBLEM || echo "read-only OK"
```

## Troubleshooting

### VM does not start

1. Check the state:

```bash
virsh list --all
```

2. If they are "shut off" even though `running = true`:

```bash
sudo systemctl status apparmor
sudo systemctl stop apparmor
sudo systemctl restart libvirtd
```

3. Check the logs:

```bash
virsh console rke2-cp-01
```

### IP does not show up

```bash
./tf.sh ips
# or
sudo virsh net-dhcp-leases default
```

Then run terraform apply again:

```bash
./tf.sh development apply
```

### Provider libvirt error

```bash
sudo systemctl status libvirtd
sudo virt-host-validate
```

## Notes

- The `default` network must be configured in Libvirt
- The password for the `ubuntu` user is automatically set to `ubuntu`
- The SSH key is configured per environment in `terraform.tfvars`
- On first boot, the VMs run `apt update && apt upgrade -y`
