#!/bin/bash

# ============================================================
# Terraform KVM/QEMU + Proxmox VM Helper Script
# ============================================================
# Dual-platform manager:
#   PLATFORM=local  (default) — runs against libvirt on this laptop
#   PLATFORM=remote — talks to Proxmox VE API at PM_API_URL
#
# Each environment has its own Terraform root under environments/<platform>/<env>.
# A leading argument matching an environment name selects it; explicit TF_ENV /
# TF_PLATFORM picks silently (automation/CI). Interactive terminal falls back
# to prompts.
#
# Rule of the lab: one platform × one environment at a time (destroy before
# switching — names, IPs and Tailscale hostnames are identical across envs).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# -------------------------------------------------------
# Platform selection (local | remote)
# -------------------------------------------------------
PLATFORM="${TF_PLATFORM:-}"
if [[ "${1:-}" == "local" || "${1:-}" == "remote" ]]; then
    PLATFORM="$1"
    shift
fi
if [[ -z "$PLATFORM" ]]; then
    if [[ -t 0 ]]; then
        while true; do
            read -rp "Platform [local/remote] (default: local): " PLATFORM
            PLATFORM="${PLATFORM,,}"
            PLATFORM="${PLATFORM:-local}"
            if [[ "$PLATFORM" == "local" || "$PLATFORM" == "remote" ]]; then
                break
            fi
            echo "Unknown platform: '$PLATFORM' -- expected local or remote." >&2
            PLATFORM=""
        done
    else
        echo "No platform given and stdin is not a terminal; using default: local." >&2
        PLATFORM="local"
    fi
fi
ENVIRONMENTS_DIR="$SCRIPT_DIR/environments/$PLATFORM"
if [[ ! -d "$ENVIRONMENTS_DIR" ]]; then
    echo "ERROR: environments/$PLATFORM does not exist." >&2
    exit 1
fi

# -------------------------------------------------------
# Environment selection (development / staging / production)
# -------------------------------------------------------
ENV="${TF_ENV:-}"
if [[ "${1:-}" == "development" || "${1:-}" == "staging" || "${1:-}" == "production" ]]; then
    ENV="$1"
    shift
fi
if [[ -z "$ENV" ]]; then
    if [[ -t 0 ]]; then
        while true; do
            read -rp "Environment [development/staging/production] (default: development): " ENV
            ENV="${ENV,,}"
            ENV="${ENV:-development}"
            if [[ "$ENV" == "development" || "$ENV" == "staging" || "$ENV" == "production" ]]; then
                break
            fi
            echo "Unknown environment: '$ENV' -- expected development, staging or production." >&2
            ENV=""
        done
    else
        echo "No environment given and stdin is not a terminal; using default: development." >&2
        ENV="development"
    fi
fi
if [[ ! -d "$ENVIRONMENTS_DIR/$ENV" ]]; then
    echo "Unknown environment: '$ENV' (no $ENVIRONMENTS_DIR/$ENV directory)." >&2
    exit 1
fi
TF_DIR="$ENVIRONMENTS_DIR/$ENV"

# VM names (kept in sync with main.tf) — distinct per platform
# local:  rke2-lbvrt-cp-01 / rke2-lbvrt-wk-01 / rke2-lbvrt-wk-02
# remote: rke2-qm-cp-01   / rke2-qm-wk-01   / rke2-qm-wk-02
if [[ "$PLATFORM" == "local" ]]; then
    VM_CP_01="rke2-lbvrt-cp-01"
    VM_WK_01="rke2-lbvrt-wk-01"
    VM_WK_02="rke2-lbvrt-wk-02"
else
    VM_CP_01="rke2-qm-cp-01"
    VM_WK_01="rke2-qm-wk-01"
    VM_WK_02="rke2-qm-wk-02"
fi

# -------------------------------------------------------
# Shared credentials / constants (read from .env when present, never committed)
# -------------------------------------------------------

# Validate Tailscale variables are set (no defaults)
ensure_tailscale_vars() {
    local missing=()

    [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]    && missing+=("TAILSCALE_AUTH_KEY")
    [[ -z "${TAILSCALE_DNS:-}" ]]         && missing+=("TAILSCALE_DNS")
    [[ -z "${TAILSCALE_TAILNET:-}" ]]     && missing+=("TAILSCALE_TAILNET")
    [[ -z "${TAILSCALE_API_TOKEN:-}" ]]   && missing+=("TAILSCALE_API_TOKEN")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required Tailscale environment variables:" >&2
        for v in "${missing[@]}"; do
            echo "  - $v" >&2
        done
        echo "" >&2
        echo "Set them before running, e.g.:" >&2
        echo "  export TAILSCALE_AUTH_KEY=\"...\"" >&2
        echo "  export TAILSCALE_DNS=\"...\"" >&2
        echo "  export TAILSCALE_TAILNET=\"...\"  # or \"-\" for default" >&2
        echo "  export TAILSCALE_API_TOKEN=\"...\"" >&2
        return 1
    fi
}

SSH_USER="ubuntu"
WAIT_INTERVAL=10
WAIT_TIMEOUT_DEFAULT=600

# Per-platform LAN addressing ground truth
if [[ "$PLATFORM" == "local" ]]; then
    # Libvirt NAT network (configs/local/network.xml); static reservations match MODULE calls below.
    VM_CP_01_IP="192.168.200.210"
    VM_WK_01_IP="192.168.200.211"
    VM_WK_02_IP="192.168.200.212"
else
    # Proxmox PVE bridge (vmbr0 on 192.168.100.0/24). IPs set via cloud-init in modules/qm_vm.
    VM_CP_01_IP="192.168.100.210"
    VM_WK_01_IP="192.168.100.211"
    VM_WK_02_IP="192.168.100.212"
fi

# -------------------------------------------------------
# Proxmox credentials (remote platform only)
# Set via env vars or .env file; never hard-coded.
# Terraform provider reads PM_API_URL / PM_USER / PM_PASSWD
# automatically, but we also export TF_VAR_pm_password for the
# null_resource SSH upload inside qm_vm (optional when tailscale/dnsmasq).
# ALL variables are REQUIRED — no defaults, no auto-creation.
# Token creation is user's responsibility in Proxmox UI.
# -------------------------------------------------------
ensure_pm_creds() {
    if [[ "$PLATFORM" != "remote" ]]; then
        return 0
    fi

    local missing=()

    [[ -z "${PM_API_URL:-}" ]]       && missing+=("PM_API_URL")
    [[ -z "${PM_USER:-}" ]]          && missing+=("PM_USER")
    [[ -z "${PM_PASSWD:-}" ]]        && missing+=("PM_PASSWD")
    [[ -z "${PM_NODE:-}" ]]          && missing+=("PM_NODE")
    [[ -z "${PM_API_TOKEN_ID:-}" ]]  && missing+=("PM_API_TOKEN_ID")
    [[ -z "${PM_API_TOKEN_SECRET:-}" ]] && missing+=("PM_API_TOKEN_SECRET")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables for remote platform:" >&2
        for v in "${missing[@]}"; do
            echo "  - $v" >&2
        done
        echo "" >&2
        echo "Set them before running, e.g.:" >&2
        echo "  export PM_API_URL=\"...\"" >&2
        echo "  export PM_USER=\"...\"" >&2
        echo "  export PM_PASSWD=\"...\"" >&2
        echo "  export PM_NODE=\"...\"" >&2
        echo "  export PM_API_TOKEN_ID=\"...\"" >&2
        echo "  export PM_API_TOKEN_SECRET=\"...\"" >&2
        echo "" >&2
        echo "Create the API token in Proxmox UI: Datacenter → Permissions → API Tokens → Add" >&2
        return 1
    fi

    # Export for Terraform provider (reads PM_API_URL, PM_USER, PM_PASSWD)
    export PM_API_URL
    export PM_USER
    export PM_PASSWD

    # Passthrough to module-level variable used by null_resource SSH upload
    export TF_VAR_pm_password="${PM_PASSWD}"
}

# Node inventory used by tailscale_start / wait_one_vm. Format:
#   name:mac:static-ip:family:id:expected-hostname
# MACs pin DHCP reservations for local/libvirt only; for remote they are ignored
# by the module but kept here so the inventory shape stays identical across paths.
# expected-hostname matches the VM name (rke2-lbvrt-* or rke2-qm-*)
NODES=(
    "${VM_CP_01}:52:54:00:a1:b2:c3:${VM_CP_01_IP}:rke2-cp:CP_01:${VM_CP_01}-${USER}-01"
    "${VM_WK_01}:52:54:00:d1:e2:f3:${VM_WK_01_IP}:rke2-wk:WK_01:${VM_WK_01}-${USER}-01"
    "${VM_WK_02}:52:54:00:aa:bb:cc:${VM_WK_02_IP}:rke2-wk:WK_02:${VM_WK_02}-${USER}-02"
)

# -------------------------------------------------------
# Package checks
# -------------------------------------------------------
check_packages() {
    echo "==> platform=$PLATFORM environment=$ENV"
    if ! command -v terraform &> /dev/null; then
        echo "Terraform not found" >&2
        return 1
    fi
    terraform -v | head -1
    if [[ "$PLATFORM" == "local" ]]; then
        local missing=()
        for pkg in qemu-system-x86 libvirt-daemon-system bridge-utils; do
            if ! dpkg -l 2>/dev/null | grep -q "^ii.*$pkg"; then
                missing+=("$pkg")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Missing packages for local platform: ${missing[*]}"
            echo "Install with: sudo apt-get install -y ${missing[*]}" >&2
        fi
    else
        # Remote needs the Terraform proxmox provider; no extra OS packages required.
        echo "Remote (Proxmox) mode — checks provider auth at 'terraform init' time."
    fi
}

# -------------------------------------------------------
# Platform-specific bootstrap helpers
# -------------------------------------------------------
ensure_network() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "network: N/A on remote (Proxmox uses vmbr0 directly)."
        return 0
    fi
    echo "Ensuring libvirt network..."
    if sudo virsh net-info local 2>/dev/null | grep -q "Active:.*yes"; then
        echo "Network already active"
    else
        sudo virsh net-start local
        sudo virsh net-autostart local
    fi
}

init_images() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "images: N/A on remote (Proxmox manages templates/storage pools)."
        return 0
    fi
    ubuntu_version="24.04"
    libvirt_img_path="/var/lib/libvirt/images"
    base_image="${libvirt_img_path}/ubuntu-${ubuntu_version}-server-cloudimg-amd64.img"
    base_image_url="https://cloud-images.ubuntu.com/releases/${ubuntu_version}/release/ubuntu-${ubuntu_version}-server-cloudimg-amd64.img"

    if [[ ! -f "$base_image" ]]; then
        echo "Base image not found at $base_image"
        echo "Downloading..."
        sudo wget -O "$base_image" "$base_image_url"
        sudo chmod 644 "$base_image"
        sudo chown libvirt-qemu:kvm "$base_image"
        echo "...Download complete"
    fi

    qcow2_image="${libvirt_img_path}/ubuntu-${ubuntu_version}.qcow2"
    if [[ ! -f "$qcow2_image" ]]; then
        echo "Ubuntu QCOW2 image not found at $qcow2_image"
        echo "Converting IMG to QCOW2..."
        sudo qemu-img convert -O qcow2 "$base_image" "$qcow2_image"
        sudo chmod 644 "$qcow2_image"
        sudo chown libvirt-qemu:kvm "$qcow2_image"
        echo "...Done"
    fi
}

recreate_network() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "recreate-network: not applicable on remote (Proxmox bridges are managed externally)." >&2
        return 1
    fi
    echo "Recreating libvirt network..."
    sudo virsh net-destroy local 2>/dev/null || true
    sudo virsh net-undefine local 2>/dev/null || true
    sudo virsh net-define "$SCRIPT_DIR/configs/local/network.xml"
    sudo virsh net-start local
    sudo virsh net-autostart local
    echo "Network recreated"
}

start_vms() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "start: not applicable on remote — use 'pmctl start <vmid>' on the Proxmox node." >&2
        return 1
    fi
    echo "Starting VMs..."
    for vm in "$VM_CP_01" "$VM_WK_01" "$VM_WK_02"; do
        sudo virsh start "$vm"
    done
    echo "VMs started"
}

stop_vms() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "stop: not applicable on remote — use 'qm shutdown <vmid>' on the Proxmox node." >&2
        return 1
    fi
    echo "Stopping VMs (graceful shutdown)..."
    for vm in "$VM_CP_01" "$VM_WK_01" "$VM_WK_02"; do
        sudo virsh shutdown "$vm"
    done
    for vm in "$VM_CP_01" "$VM_WK_01" "$VM_WK_02"; do
        echo "Waiting for $vm to shutdown..."
        for _ in {1..60}; do
            if ! sudo virsh list | grep -q "$vm"; then
                echo "$vm stopped"
                break
            fi
            sleep 1
        done
    done
}

force_stop_vms() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "force-stop: not applicable on remote — use 'qm destroy <vmid>' on the Proxmox node." >&2
        return 1
    fi
    echo "Force stopping VMs..."
    for vm in "$VM_CP_01" "$VM_WK_01" "$VM_WK_02"; do
        sudo virsh destroy "$vm"
    done
    echo "VMs destroyed"
}

get_ips() {
    if [[ "$PLATFORM" != "local" ]]; then
        echo "ips: on remote, run 'terraform -chdir=$TF_DIR output vm_ips' instead."
        return 0
    fi
    echo "Current DHCP leases:"
    sudo virsh net-dhcp-leases default
    echo ""
    echo "VM status:"
    sudo virsh list --all
}

# -------------------------------------------------------
# SSH helper
# -------------------------------------------------------
ssh_vm() {
    local ip="$1"
    shift
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${SSH_USER}@${ip}" "$@"
}

wait_ssh() {
    local name="$1" ip="$2" deadline="$3" now
    echo "==> ${name} (${ip}): waiting for SSH..."
    while true; do
        now=$(date +%s)
        if (( now >= deadline )); then
            echo "TIMEOUT: ${name}: SSH never came up."
            return 1
        fi
        if ssh_vm "$ip" "true" 2>/dev/null; then
            echo "OK: ${name} SSH reachable"
            return 0
        fi
        echo "    ... SSH unavailable, retrying in ${WAIT_INTERVAL}s"
        sleep "$WAIT_INTERVAL"
    done
}

# Wait for a single VM: cloud-init done + tailscale up (100.x IP). Returns 0 on success.
wait_one_vm() {
    local name="$1" ip="$2" deadline="$3" ci ts_ip now
    echo "==> ${name} (${ip}): waiting for cloud-init + tailscale..."
    while true; do
        now=$(date +%s)
        if (( now >= deadline )); then
            echo "TIMEOUT: ${name} did not become ready in time."
            return 1
        fi
        if ! ssh_vm "$ip" "true" 2>/dev/null; then
            echo "    ... SSH unavailable, retrying in ${WAIT_INTERVAL}s"
            sleep "$WAIT_INTERVAL"
            continue
        fi
        ci=$(ssh_vm "$ip" "cloud-init status 2>/dev/null" || true)
        if ! echo "$ci" | grep -q ": done"; then
            echo "    ... cloud-init: ${ci:-unknown}"
            sleep "$WAIT_INTERVAL"
            continue
        fi
        ts_ip=$(ssh_vm "$ip" "tailscale ip -4 2>/dev/null" | head -1 || true)
        if echo "$ts_ip" | grep -qE '^100\.'; then
            echo "OK: ${name} cloud-init done, tailscale ${ts_ip}"
            return 0
        fi
        echo "    ... cloud-init done, tailscale not up yet"
        sleep "$WAIT_INTERVAL"
    done
}

# Wait for all VMs. Usage: wait_all_vms [timeout_seconds]
wait_all_vms() {
    local timeout="${1:-$WAIT_TIMEOUT_DEFAULT}"
    local deadline failed=0
    deadline=$(( $(date +%s) + timeout ))
    echo "Waiting for cloud-init + tailscale on all VMs (timeout ${timeout}s)..."
    wait_one_vm "$VM_CP_01" "$VM_CP_01_IP" "$deadline" || failed=1
    wait_one_vm "$VM_WK_01" "$VM_WK_01_IP" "$deadline" || failed=1
    wait_one_vm "$VM_WK_02" "$VM_WK_02_IP" "$deadline" || failed=1
    if (( failed != 0 )); then
        echo "DONE with errors: one or more VMs are not ready. Check with: $0 ips"
        return 1
    fi
    echo "All VMs are ready (cloud-init done + tailscale up)."
}

# Bring Tailscale up on all nodes after a plain start. See original comment block
# in tf.sh (lines 231-362) for the full rationale — identity verification happens
# twice (hostname exact-match + pairwise distinctness) before any state change.
tailscale_start() {
    ensure_tailscale_vars || return 1

    local timeout="${1:-$WAIT_TIMEOUT_DEFAULT}"
    local deadline failed=0
    deadline=$(( $(date +%s) + timeout ))
    local names=() ips=() families=() ids=() expected=() hostnames=("" "" "")
    local spec rest
    for spec in "${NODES[@]}"; do
        expected+=("${spec##*:}")
        rest="${spec%:*}"
        ids+=("${rest##*:}")
        rest="${rest%:*}"
        families+=("${rest##*:}")
        rest="${rest%:*}"
        ips+=("${rest##*:}")
        rest="${rest%:*}"
        names+=("${rest%%:*}")
    done
    local i j name ip remote_name ts_ip

    echo "Bringing Tailscale up on all VMs (timeout ${timeout}s)..."
    for i in 0 1 2; do
        name="${names[$i]}"
        ip="${ips[$i]}"
        id="${ids[$i]}"
        wait_ssh "${id}" "$ip" "$deadline" || { failed=1; continue; }
        remote_name=$(ssh_vm "$ip" "hostname" 2>/dev/null | tr -d '\r\n ' || true)
        if [[ -z "$remote_name" ]]; then
            echo "FAILED: ${id} (${ip}): SSH answers but hostname is unreadable."
            failed=1
            continue
        fi
        echo "OK: ${id} (${ip}): reached host '${remote_name}'"
        if [[ "$remote_name" != "${expected[$i]}" ]]; then
            echo "FAILED: ${id} (${ip}): host '${remote_name}' is not '${expected[$i]}' -- wrong box, swapped IP or renamed host, refusing to touch it."
            failed=1
            continue
        fi
        hostnames[$i]="$remote_name"
    done
    for i in 0 1 2; do
        for j in 0 1 2; do
            if (( j > i )) && [[ -n "${hostnames[$i]}" && "${hostnames[$i]}" == "${hostnames[$j]}" ]]; then
                echo "FAILED: ${ids[$i]} (${ips[$i]}) and ${ids[$j]} (${ips[$j]}) both reach '${hostnames[$i]}' -- duplicate IP or stale DHCP lease. Refusing to touch either."
                failed=1
                hostnames[$i]=""
                hostnames[$j]=""
            fi
        done
    done
    for i in 0 1 2; do
        [[ -n "${hostnames[$i]}" ]] || continue
        name="${names[$i]}"
        id="${ids[$i]}"
        ip="${ips[$i]}"
        ts_ip=$(ssh_vm "$ip" "tailscale ip -4 2>/dev/null" | head -1 || true)
        if echo "$ts_ip" | grep -qE '^100\.'; then
            echo "OK: ${id} tailscale already up (${ts_ip}), skipping re-auth"
            continue
        fi
        if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
            echo "FAILED: ${id}: Tailscale session is down and no auth key is set. Export TAILSCALE_AUTH_KEY and re-run."
            failed=1
            continue
        fi
        echo "==> ${id}: re-authenticating tailscale (non-interactive)..."
        if ! ssh_vm "$ip" "sudo systemctl enable --now tailscaled >/dev/null 2>&1"; then
            echo "FAILED: ${id}: could not enable/start tailscaled."
            failed=1
            continue
        fi
        if ! ssh_vm "$ip" "sudo tailscale up --authkey='${TAILSCALE_AUTH_KEY}' --hostname=${name} --accept-dns" < /dev/null; then
            echo "FAILED: ${id}: non-interactive 'tailscale up' failed (key may be expired -- generate a new reusable one)."
            failed=1
            continue
        fi
        ts_ip=$(ssh_vm "$ip" "tailscale ip -4 2>/dev/null" | head -1 || true)
        if echo "$ts_ip" | grep -qE '^100\.'; then
            echo "OK: ${id} tailscale up (${ts_ip})"
        else
            echo "FAILED: ${id}: no 100.x address after re-auth (got '${ts_ip:-none}')."
            failed=1
        fi
    done
    if (( failed != 0 )); then
        echo "DONE with errors: Tailscale is not up on every VM."
        return 1
    fi
    echo "Tailscale is up on all VMs."
}

# Ensure the Floci-emulated S3 bucket used for remote state exists
# (idempotent). Also removes leftover DynamoDB lock table from the old era.
# REQUIRES: FLOCI_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION, AWS_EC2_METADATA_DISABLED
# All must be set in the environment — no defaults provided.
ensure_state_backend() {
    local missing=()

    [[ -z "${FLOCI_ENDPOINT:-}" ]]                && missing+=("FLOCI_ENDPOINT")
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]             && missing+=("AWS_ACCESS_KEY_ID")
    [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]         && missing+=("AWS_SECRET_ACCESS_KEY")
    [[ -z "${AWS_DEFAULT_REGION:-}" ]]            && missing+=("AWS_DEFAULT_REGION")
    [[ -z "${AWS_EC2_METADATA_DISABLED:-}" ]]     && missing+=("AWS_EC2_METADATA_DISABLED")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables for state backend:" >&2
        for v in "${missing[@]}"; do
            echo "  - $v" >&2
        done
        echo "" >&2
        echo "Set them before running, e.g.:" >&2
        echo "  export FLOCI_ENDPOINT=\"...\"" >&2
        echo "  export AWS_ACCESS_KEY_ID=\"...\"" >&2
        echo "  export AWS_SECRET_ACCESS_KEY=\"...\"" >&2
        echo "  export AWS_DEFAULT_REGION=\"...\"" >&2
        echo "  export AWS_EC2_METADATA_DISABLED=\"...\"" >&2
        return 1
    fi

    local endpoint="${FLOCI_ENDPOINT}"

    if ! command -v aws &> /dev/null; then
        echo "aws CLI not found (needed for remote-state bootstrap)" >&2
        return 1
    fi
    if ! aws --endpoint-url "$endpoint" s3api head-bucket --bucket astrolumina-terraform-state 2>/dev/null; then
        echo "Creating S3 state bucket..."
        aws --endpoint-url "$endpoint" s3 mb s3://astrolumina-terraform-state --region "$AWS_DEFAULT_REGION" || return 1
        aws --endpoint-url "$endpoint" s3api put-bucket-versioning --bucket astrolumina-terraform-state --versioning-configuration Status=Enabled || return 1
    else
        echo "S3 state bucket already exists"
    fi
    if aws --endpoint-url "$endpoint" dynamodb describe-table --table-name terraform-state-locks &>/dev/null; then
        echo "Removing leftover DynamoDB lock table (locking is S3-native now)..."
        aws --endpoint-url "$endpoint" dynamodb delete-table --table-name terraform-state-locks --region "$AWS_DEFAULT_REGION" || return 1
    else
        echo "No leftover DynamoDB lock table"
    fi
}

# Status helpers — platform-aware
status_vms() {
    if [[ "$PLATFORM" == "local" ]]; then
        echo "==> local VMs:"
        sudo virsh list --all
    else
        echo "==> remote state: $TF_DIR"
        echo "Run: terraform -chdir=$TF_DIR output vm_details"
        echo "Or check Proxmox UI at ${PM_API_URL:-https://192.168.100.200:8006/}"
    fi
}

# ============================================================
# Pre-flight checks for remote (Proxmox) environment.
#
# Usage: ./tf.sh [platform] [env] init-pve [--auto-create-template]
#   --auto-create-template : if the cloud-init template doesn't exist,
#     download Ubuntu 24.04 cloud image and create it via qm commands on
#     the Proxmox node (requires SSH access with root key auth).
#
# This command does NOT modify any VMs or templates unless --auto-create-template
# is passed AND the template is missing. It always reports the full status.
#
# Prerequisites documented in preconditions.md:
#   A) Firewall rules (laptop → PVE TCP 8006 + 22) — external to PVE
#   B) API token / credentials exported as PM_API_TOKEN_ID / PM_API_TOKEN_SECRET
#      (or PM_USER / PM_PASSWD for basic auth)
#   C) Storage pool 'local' — default on PVE
#   D) Bridge 'vmbr0' — default on PVE
#   E) Cloud-init template 'ubuntu-24.04-cloudinit-template' — see below
# ============================================================
init_pve_preflight() {
    local auto_create_template=false
    shift  # remove the command name from args; remaining args are from CLI
    for a in "$@"; do
        case "$a" in
            --auto-create-template) auto_create_template=true ;;
        esac
    done

    if [[ "$PLATFORM" != "remote" ]]; then
        echo "init-pve is only valid for the remote (Proxmox) platform." >&2
        exit 1
    fi

    ensure_pm_creds

    local api_url pm_host api_port token_id token_secret
    api_url="${PM_API_URL:-https://192.168.100.200:8006/}"
    pm_host="$(echo "$api_url" | sed -E 's|https?://||; s|:.*/$||; s|/$||')"
    api_port="$(echo "$api_url" | grep -oE ':[0-9]+' | tr -d ':' || true)"
    api_port="${api_port:-8006}"
    token_id="${PM_API_TOKEN_ID:-${PM_USER}}"
    token_secret="${PM_API_TOKEN_SECRET:-${PM_PASSWD}}"

    echo ""
    echo "============================================================"
    echo " Proxmox pre-flight checks  —  host=${pm_host}:${api_port}"
    echo "============================================================"
    echo ""

    # --- Check 1: HTTP connectivity ------------------------------------------------
    echo "[1/7] API reachability (${api_url})"
    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "${api_url}api2/json/version" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" || "$http_code" == "401" || "$http_code" == "403" ]]; then
        echo "    ✅ OK  (HTTP ${http_code})"
    elif [[ "$http_code" == "000" ]]; then
        echo "    ❌ FAIL — cannot reach ${pm_host}:${api_port}" >&2
        echo "    Hint: verify firewall rule on your LAN allows TCP ${api_port} from this machine to ${pm_host}." >&2
        echo ""
        echo "    To open the port temporarily on the Proxmox node (run ON the PVE host):"
        echo "      iptables -I INPUT -p tcp -s $(hostname -I | awk '{print $1}' | cut -d. -f1-3).0/24 --dport ${api_port} -j ACCEPT"
        echo ""
    else
        echo "    ⚠️  Unexpected HTTP code ${http_code}"
    fi
    echo ""

    # --- Check 2: Authentication ----------------------------------------------------
    echo "[2/7] Authentication (API token)"
    if [[ -z "${token_secret}" ]]; then
        echo "    ❌ MISSING — set PM_API_TOKEN_SECRET (preferred) or PM_PASSWD" >&2
        echo "    Recommended (create token on Proxmox):"
        echo "      pveum token add root@pam astroterra --comment \"Terraform $(date +%F)\""
        echo "      export PM_API_TOKEN_ID=root@pam!astroterra=UUID"
        echo "      export PM_API_TOKEN_SECRET=<the-secret-value>"
    else
        local auth_result
        auth_result=$(curl -sS --max-time 5 \
            -H "Authorization: PVEAPIToken=${token_id}=${token_secret}" \
            "${api_url}api2/json/access/ticket" 2>/dev/null | head -c 200 || true)
        if echo "$auth_result" | grep -qi '"data"'; then
            echo "    ✅ OK  (token authenticated as ${token_id})"
        else
            echo "    ⚠️  Auth may be invalid — response:"
            echo "    $auth_result" | head -3
            echo "    Continuing anyway; Terraform init will surface real errors."
        fi
    fi
    echo ""

    # --- Check 3: Storage pools -----------------------------------------------------
    echo "[3/7] Storage pools"
    local storage_json
    storage_json=$(curl -sS --max-time 5 \
        -H "Authorization: PVEAPIToken=${token_id}=${token_secret}" \
        "${api_url}api2/json/storage" 2>/dev/null || true)
    local has_local has_content
    has_local=$(echo "$storage_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    names = [x.get('storage','') for x in (d.get('data') or [])]
    print(','.join(names))
except: print('')
" 2>/dev/null || true)
    if echo "$has_local" | grep -q '^local'; then
        echo "    ✅ Storage pool 'local' present (also available: ${has_local})"
    else
        echo "    ❌ MISSING storage pool 'local'" >&2
        echo "    Create it (on PVE node):"
        echo "      pvesm add dir local -path /var/lib/vz"
    fi
    echo ""

    # --- Check 4: Network bridge vmbr0 ----------------------------------------------
    echo "[4/7] Network bridge 'vmbr0'"
    local ssh_br=""
    ssh_br=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${pm_ssh_user:-root}@${pm_host}" \
        "ip -o link show vmbr0 2>/dev/null | awk -F': ' '{print \$2}' | head -1" 2>/dev/null || true)
    if [[ -n "$ssh_br" && "$ssh_br" != "lo" ]]; then
        local vmbr_ip
        vmbr_ip=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "${pm_ssh_user:-root}@${pm_host}" \
            "ip -4 addr show vmbr0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | head -1 || echo unknown" \
            2>/dev/null || true)
        vmbr_ip="${vmbr_ip:-unknown}"
        echo "    ✅ vmbr0 exists  (${vmbr_ip})"
    else
        echo "    ❌ 'vmbr0' not found (checked via SSH '${pm_ssh_user:-root}@${pm_host}')" >&2
        echo "    Configure in /etc/network/interfaces on the Proxmox node:"
        cat <<'EOFBRIDGE'
    auto vmbr0
    iface vmbr0 inet static
        address 192.168.100.200/24   # ← adjust to your host IP
        gateway 192.168.100.1
        bridge-ports enp1s0           # ← your physical NIC name
        bridge-stp off
        bridge-fd 0
EOFBRIDGE
    fi
    echo ""

    # --- Check 5: Snippets directory -----------------------------------------------
    echo "[5/7] Snippets directory (/var/lib/vz/snippets)"
    local snippets_ok=false
    snippets_ok=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${pm_ssh_user:-root}@${pm_host}" \
        "test -d /var/lib/vz/snippets && echo yes || echo no" 2>/dev/null || echo "no")
    if [[ "$snippets_ok" == "yes" ]]; then
        echo "    ✅ /var/lib/vz/snippets exists"
    else
        echo "    ⚠️  /var/lib/vz/snippets missing (used when cicustom user-data needed)"
        echo "    Fix (on PVE node): sudo mkdir -p /var/lib/vz/snippets"
    fi
    echo ""

    # --- Check 6: Cloud-init template -----------------------------------------------
    echo "[6/7] Cloud-init template 'ubuntu-24.04-cloudinit-template'"
    local tmpl_exists=false
    tmpl_exists=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${pm_ssh_user:-root}@${pm_host}" \
        "qm list 2>/dev/null | grep -i 'ubuntu-24.04-cloudinit-template' | awk '{print \$NF}' | head -1" \
        2>/dev/null || true)
    if [[ -n "$tmpl_exists" ]]; then
        echo "    ✅ Template found  (ID $(qm list 2>/dev/null | grep -i 'ubuntu-24.04' | head -1))"
    else
        echo "    ❌ Template NOT FOUND" >&2
        echo ""
        echo "    Two options to proceed:"
        echo ""
        echo "    Option A — one-liner on the Proxmox node (manual copy/paste):"
        echo "      See environments/remote/preconditions.md §Manual one-liner"
        echo ""
        echo "    Option B — let tf.sh create it automatically (--auto-create-template):"
        echo "      ./tf.sh remote init-pve --auto-create-template"
        echo "      (Requires passwordless root SSH or PM_PASSWORD set)"
        if [[ "$auto_create_template" == "true" ]]; then
            echo ""
            echo "    → Running auto-creation now..."
            _create_cloudinit_template_on_host "$pm_host" || {
                echo ""
                echo "    Auto-creation failed. Falling back to manual steps above." >&2
                return 1
            }
            echo "    ✅ Template created successfully."
        fi
    fi
    echo ""

    # --- Check 7: Optional — SSH reachability for snippet upload --------------------
    echo "[7/7] SSH reachability (for optional snippet upload)"
    local ssh_ok=false
    ssh_ok=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        "${pm_ssh_user:-root}@${pm_host}" \
        "echo ok" 2>/dev/null || true)
    if [[ "$ssh_ok" == "ok" ]]; then
        echo "    ✅ SSH login works as '${pm_ssh_user:-root}@${pm_host}'"
        echo "       (snippet upload will work when cicustom user-data is needed)"
    else
        echo "    ⚠️  SSH unreachable as '${pm_ssh_user:-root}@${pm_host}'"
        echo "       The null_resource that uploads cicustom snippets won't run."
        echo "       If you don't use tailscale/dnsmasq, this is harmless."
    fi
    echo ""

    echo "============================================================"
    echo " Pre-flight complete."
    echo " When all ❌ items are resolved, run:"
    echo "   ./tf.sh remote <env> apply"
    echo "============================================================"
    echo ""
}

# Internal helper: create the cloud-init template on a Proxmox node via SSH.
_create_cloudinit_template_on_host() {
    local host="$1"
    local tmp_script="/tmp/op/_pve_setup_tmpl_$$ .sh"

    # Build an SSH command string once; used by each remote step.
    local ssh_base="ssh -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no ${host}"
    if [[ -n "${PM_PASSWORD:-}" ]]; then
        if ! command -v sshpass &>/dev/null; then
            echo "    ERROR: sshpass not installed (needed for password-based SSH)." >&2
            echo "    Install with: sudo apt-get install -y sshpass" >&2
            return 1
        fi
        ssh_base="sshpass -p '${PM_PASSWORD}' ${ssh_base}"
    fi

    cat >"$tmp_script" <<SETUPEOF
#!/bin/bash
set -euo pipefail
HOST="${host}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=60 -o StrictHostKeyChecking=no \${HOST}"
if [[ -n "${PM_PASSWORD:-}" ]]; then
    SSH="sshpass -p '${PM_PASSWORD}' \${SSH}"
fi

echo "[setup] downloading Ubuntu 24.04 cloud image ..."
\${SSH} 'wget -qO /tmp/ubuntu-24.04-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img && echo done-download' \
    || { echo "  download failed" >&2; exit 1; }

echo "[setup] creating VM 9000 ..."
\${SSH} 'qm create 9000 --memory 2048 --core 2 --sockets 1 --cpu host \
    --name ubuntu-24.04-cloudinit-template --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-single' \
    || { echo "  qm create failed" >&2; exit 1; }

echo "[setup] importing disk to local-lvm ..."
\${SSH} 'qm importdisk 9000 /tmp/ubuntu-24.04-server-cloudimg-amd64.img local-lvm && rm -f /tmp/ubuntu-24.04-server-cloudimg-amd64.img' \
    || { echo "  importdisk failed" >&2; exit 1; }

echo "[setup] configuring cloud-init CD, serial console, boot order, template ..."
\${SSH} 'qm set 9000 --ide2 local:cloudinit && \
    qm set 9000 --boot order=scsi0 && \
    qm set 9000 --serial0 socket --vga serial0 && \
    qm template 9000 && \
    echo TEMPLATE_READY' \
    || { echo "  template setup failed" >&2; exit 1; }

echo "Template ubuntu-24.04-cloudinit-template created (VM 9000)."
SETUPEOF
    chmod +x "$tmp_script"
    bash "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}

# -------------------------------------------------------
# Helper: Download Ubuntu ISO to ~/ISOs/
# -------------------------------------------------------
download_iso() {
    local iso_dir="${HOME}/ISOs"
    local iso_name="ubuntu-24.04-server-cloudimg-amd64.img"
    local iso_path="${iso_dir}/${iso_name}"
    local iso_url="https://cloud-images.ubuntu.com/releases/24.04/release/${iso_name}"

    echo "Downloading Ubuntu 24.04 cloud image to ${iso_path}..."
    mkdir -p "${iso_dir}"

    if [[ -f "${iso_path}" ]]; then
        echo "ISO already exists at ${iso_path}"
        return 0
    fi

    wget -O "${iso_path}" "${iso_url}" || {
        echo "ERROR: Failed to download ISO" >&2
        return 1
    }

    echo "✅ Downloaded: ${iso_path}"
    ls -lh "${iso_path}"
}

# -------------------------------------------------------
# Helper: Upload ISO to Proxmox storage
# -------------------------------------------------------
upload_iso() {
    ensure_pm_creds || return 1

    local iso_dir="${HOME}/ISOs"
    local iso_name="ubuntu-24.04-server-cloudimg-amd64.img"
    local iso_path="${iso_dir}/${iso_name}"
    local pm_storage="${PM_STORAGE:-local}"

    if [[ ! -f "${iso_path}" ]]; then
        echo "ERROR: ISO not found at ${iso_path}" >&2
        echo "Run: ./tf.sh remote ${ENV} download-iso" >&2
        return 1
    fi

    echo "Uploading ISO to Proxmox storage '${pm_storage}' on node '${PM_NODE}'..."

    local api_url="${PM_API_URL}"
    local token_id="${PM_API_TOKEN_ID}"
    local token_secret="${PM_API_TOKEN_SECRET}"

    # Upload via Proxmox API
    curl -k -sS -X POST \
        -H "Authorization: PVEAPIToken=${token_id}=${token_secret}" \
        -F "content=iso" \
        -F "filename=@${iso_path}" \
        "${api_url}api2/json/nodes/${PM_NODE}/storage/${pm_storage}/upload" | \
        python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if d.get('data') is not None:
        print('✅ Upload successful')
    else:
        print('Response:', json.dumps(d))
        sys.exit(1)
except Exception as e:
    print('Parse error:', e)
    sys.exit(1)
" || {
        echo "ERROR: Upload failed" >&2
        return 1
    }

    echo "✅ ISO uploaded to Proxmox storage '${pm_storage}'"
}

# -------------------------------------------------------
# Helper: Create cloud-init template on Proxmox
# -------------------------------------------------------
create_template() {
    ensure_pm_creds || return 1

    echo "Creating cloud-init template on Proxmox node '${PM_NODE}'..."
    _create_cloudinit_template_on_host "${PM_NODE}" || {
        echo "ERROR: Template creation failed" >&2
        return 1
    }
    echo "✅ Template created successfully"
}


case ${1:-} in
    "init")
        check_packages
        ensure_network
        init_images
        ensure_state_backend || exit 1
        ensure_pm_creds
        terraform -chdir="$TF_DIR" init
        ;;
    "fmt")
        terraform -chdir="$TF_DIR" fmt -recursive
        ;;
    "validate")
        terraform -chdir="$TF_DIR" validate
        ;;
    "apply")
        ensure_tailscale_vars || exit 1
        export TF_VAR_tailscale_auth_key="$TAILSCALE_AUTH_KEY"
        export TF_VAR_tailscale_dns="$TAILSCALE_DNS"
        ensure_pm_creds
        terraform -chdir="$TF_DIR" apply -auto-approve || exit 1
        wait_all_vms "${2:-$WAIT_TIMEOUT_DEFAULT}" || exit 1
        ;;
    "plan")
        ensure_tailscale_vars || exit 1
        export TF_VAR_tailscale_auth_key="$TAILSCALE_AUTH_KEY"
        export TF_VAR_tailscale_dns="$TAILSCALE_DNS"
        ensure_pm_creds
        terraform -chdir="$TF_DIR" plan
        ;;
    "destroy")
        terraform -chdir="$TF_DIR" destroy -auto-approve
        ;;
    "start")
        start_vms || exit 1
        tailscale_start "${2:-$WAIT_TIMEOUT_DEFAULT}" || exit 1
        ;;
    "stop")
        stop_vms
        ;;
    "force-stop")
        force_stop_vms
        ;;
    "ips")
        get_ips
        ;;
    "wait")
        wait_all_vms "${2:-$WAIT_TIMEOUT_DEFAULT}"
        ;;
    "recreate-network")
        recreate_network
        ;;
    "status")
        status_vms
        ;;
    "init-pve")
        init_pve_preflight "${2:-}" "${3:-}"
        ;;
    "download-iso")
        download_iso
        ;;
    "upload-iso")
        upload_iso
        ;;
    "create-template")
        create_template
        ;;
    *)
        cat <<EOF
Terraform KVM/QEMU + Proxmox Helper
====================================
Platform : $PLATFORM (set TF_PLATFORM or pass as first arg)
Env      : $ENV  (set TF_ENV or pass as second arg)
TF dir   : $TF_DIR

Usage: $0 [local|remote] [environment] [command]

Commands:
  init              - Download images / check deps, bootstrap S3 state bucket, terraform init
  fmt               - Reformat .tf files recursively
  validate          - Dry-check syntax and module references
  plan              - Show what apply would do
  apply             - Create / update VMs; then wait for cloud-init + tailscale, then dns-sync
  destroy           - Destroy everything managed by this environment
  start [timeout]   - Start VMs (local only), then bring Tailscale up on each node
  stop              - Graceful shutdown VMs (local only)
  force-stop        - Force stop VMs (local only)
  ips               - Show DHCP leases / VM status (local) or suggest remote alternative
  wait [timeout]    - Wait for cloud-init done + tailscale up on all VMs
  status            - Show running VMs
  init-pve          - Pre-flight checks for remote (Proxmox): connectivity, auth, storage, bridge, template
  --auto-create-template  - optional flag for init-pve; creates cloud-init template via SSH if missing
  recreate-network  - Recreate libvirt network (local only)
  download-iso      - Download Ubuntu 24.04 cloud image to ~/ISOs/ (remote)
  upload-iso        - Upload ISO to Proxmox storage (remote)
  create-template   - Create cloud-init template VM 9000 on Proxmox (remote)

Examples:
  $0 init
  $0 remote init
  $0 staging apply
  $0 remote staging apply
  TF_ENV=production TF_PLATFORM=local $0 apply
  TF_PLATFORM=remote $0 wait
  # Remote setup sequence:
  $0 remote development download-iso
  $0 remote development upload-iso
  $0 remote development create-template
  $0 remote development apply
EOF
        exit 1
        ;;
esac
