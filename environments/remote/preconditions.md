# Proxmox Pre-deployment Prerequisites

## Quick reference — what must exist BEFORE `./tf.sh remote <env> apply`

### Category A: General PVE infra (ONE-TIME per host)
| # | Item | Action | Verify |
|---|------|--------|--------|
| 1 | Firewall rule | Allow TCP 8006 + 22 from laptop → `192.168.100.200` | External — must be done on your LAN router or host iptables |
| 2 | Storage pool `local` | Default on PVE; skip if already present | `pvesm status` on PVE node |
| 3 | Bridge `vmbr0` | Default on PVE; skip if already present | `ip addr show vmbr0` on PVE node |
| 4 | API token for `root@pam` | Run on PVE: `pveum token add root@pam astroterra --comment "Terraform"` | Export `PM_API_TOKEN_ID=root@pam!astroterra=UUID` and `PM_API_TOKEN_SECRET=<value>` |

### Category B: Cloud-init template (required)
One cloud-init-ready VM template named `ubuntu-24.04-cloudinit-template` (ID 9000).
Create it ON THE PROXMOX NODE with these commands:
```bash
wget -qO /tmp/ubuntu-24.04-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
qm create 9000 --memory 2048 --core 2 --sockets 1 --cpu host \
  --name ubuntu-24.04-cloudinit-template --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single
qm importdisk 9000 /tmp/ubuntu-24.04-server-cloudimg-amd64.img local-lvm
rm -f /tmp/ubuntu-24.04-server-cloudimg-amd64.img
qm set 9000 --ide2 local:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm template 9000
echo "✅ Template ready"
```

### Category C: Runs via Terraform (no manual step needed)
Each VM clone, disk, cloud-init config, and (optionally) snippet upload is done by terraform.

---

## Automated pre-flight checker

```bash
# Run checks without making changes (read-only):
export PM_API_URL=https://192.168.100.200:8006/
export PM_API_TOKEN_ID=root@pam!astroterra=<UUID>
export PM_API_TOKEN_SECRET=<secret>
./tf.sh remote init-pve

# Or auto-create the cloud-init template if missing (requires root SSH key access):
./tf.sh remote init-pve --auto-create-template
```

Output reports ✅ PASS / ❌ MISSING / ⚠️ ACTION_REQUIRED per item.
