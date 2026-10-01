#!/usr/bin/env bash
# Start one audit12 libvirt guest on a fresh or previously created overlay.
set -euo pipefail

fail() {
    printf 'AUDIT12 VM: STOP: %s\n' "$*" >&2
    exit 1
}

mode=create
if [[ $# -eq 1 && $1 == --existing-overlay ]]; then
    mode=existing
elif [[ $# -ne 0 ]]; then
    fail 'usage: audit12-vm-start.sh [--existing-overlay]'
fi
[[ $EUID -eq 0 ]] || fail 'run with sudo -v && sudo -n bash scripts/audit12-vm-start.sh'
[[ $(uname -r) == 6.18.53-lockdown-t14g3-audit12 ]] ||
    fail 'the running kernel is not audit12'

for tool in virsh qemu-img virt-install chown chmod python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing command: $tool"
done

base=/var/lib/libvirt/images/lockdown-audit9-vmtest.qcow2
seed=/var/lib/libvirt/images/lockdown-audit9-vmtest-seed.iso
overlay=/var/lib/libvirt/images/lockdown-audit12-vmtest-overlay.qcow2
domain=lockdown-audit12-vmtest

printf 'AUDIT12 VM: checking guest inputs and libvirt state\n'
[[ -r $base ]] || fail "base image is unreadable: $base"
[[ -r $seed ]] || fail "seed ISO is unreadable: $seed"
if virsh -c qemu:///system dominfo "$domain" >/dev/null 2>&1; then
    fail "domain already exists; inspect it before retrying: $domain"
fi
network_info=$(virsh -c qemu:///system net-info default) ||
    fail 'cannot inspect the default libvirt network'
grep -Eq '^Active:[[:space:]]+yes$' <<< "$network_info" ||
    fail 'the default libvirt network is not active'

if [[ $mode == create ]]; then
    [[ ! -e $overlay ]] || fail "overlay already exists; use --existing-overlay only after inspection: $overlay"
    printf 'AUDIT12 VM: checking the read-only base image\n'
    qemu-img check "$base" || fail 'base image check failed'
    printf 'AUDIT12 VM: creating a separate copy-on-write overlay\n'
    qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay"
    chown libvirt-qemu:kvm "$overlay"
    chmod 0640 "$overlay"
else
    [[ -r $overlay ]] || fail "existing overlay is unreadable: $overlay"
    printf 'AUDIT12 VM: checking the existing overlay and its backing path\n'
    info=$(qemu-img info --output=json "$overlay") || fail 'cannot read overlay metadata'
    backing=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("full-backing-filename", ""))' <<< "$info")
    format=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("format", ""))' <<< "$info")
    [[ $backing == "$base" && $format == qcow2 ]] ||
        fail "overlay backing or format differs from the audit12 test design: $overlay"
    qemu-img check "$overlay" || fail 'overlay image check failed'
fi

printf 'AUDIT12 VM: launching the transient guest\n'
if ! virt-install --connect qemu:///system \
    --name "$domain" --virt-type kvm --import --transient \
    --memory 2048 --vcpus 2 --cpu host-passthrough --osinfo generic \
    --disk "path=$overlay,format=qcow2,bus=virtio" \
    --disk "path=$seed,device=cdrom,format=raw,readonly=on" \
    --network network=default,model=virtio \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --graphics none --console pty,target.type=serial --noautoconsole; then
    fail "guest launch failed; overlay retained at $overlay"
fi

printf 'AUDIT12 VM: final domain state\n'
state=$(virsh -c qemu:///system domstate "$domain") ||
    fail "transient domain is no longer present; overlay retained at $overlay"
printf '%s\n' "$state"
[[ $state == running ]] || fail "guest is not running; overlay retained at $overlay"
