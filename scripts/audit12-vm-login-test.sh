#!/usr/bin/env bash
# Provision a disposable audit12 guest with a locally entered console password.
set -euo pipefail

fail() {
    printf 'AUDIT12 login VM: STOP: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 0 ]] || fail 'this command takes no arguments'
[[ $EUID -eq 0 ]] || fail 'run with sudo -v && sudo -n bash scripts/audit12-vm-login-test.sh'
[[ $(uname -r) == 6.18.53-lockdown-t14g3-audit12 ]] ||
    fail 'the running kernel is not audit12'

for tool in virsh qemu-img cloud-localds virt-install openssl; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing command: $tool"
done

base=/var/lib/libvirt/images/lockdown-audit9-vmtest.qcow2
overlay=/var/lib/libvirt/images/lockdown-audit12-login-overlay.qcow2
seed=/var/lib/libvirt/images/lockdown-audit12-login-seed.iso
domain=lockdown-audit12-login
guest_mac=52:54:00:12:00:12

printf 'AUDIT12 login VM: checking the host and test paths\n'
[[ -r $base ]] || fail "base image is unreadable: $base"
[[ ! -e $overlay ]] || fail "overlay already exists; inspect before retrying: $overlay"
[[ ! -e $seed ]] || fail "seed already exists; inspect before retrying: $seed"
if virsh -c qemu:///system dominfo "$domain" >/dev/null 2>&1; then
    fail "domain already exists: $domain"
fi
if virsh -c qemu:///system dominfo lockdown-audit12-vmtest >/dev/null 2>&1; then
    fail 'the previous audit12 test guest is still running; shut it down first'
fi
network_info=$(virsh -c qemu:///system net-info default) ||
    fail 'cannot inspect the default libvirt network'
grep -Eq '^Active:[[:space:]]+yes$' <<< "$network_info" ||
    fail 'the default libvirt network is not active'
qemu-img check "$base" || fail 'base image check failed'

printf 'Choose a password for the disposable guest account audit12.\n' > /dev/tty
printf 'The password is hidden as you type and is never printed or saved in plaintext.\n' > /dev/tty
printf 'Guest password: ' > /dev/tty
IFS= read -r -s guest_password < /dev/tty || fail 'could not read password from terminal'
printf '\nConfirm guest password: ' > /dev/tty
IFS= read -r -s guest_password_confirm < /dev/tty || fail 'could not confirm password'
printf '\n' > /dev/tty
[[ ${#guest_password} -ge 12 ]] || fail 'choose at least 12 characters'
[[ $guest_password == "$guest_password_confirm" ]] || fail 'passwords did not match'
unset guest_password_confirm
password_hash=$(printf '%s\n' "$guest_password" | openssl passwd -6 -stdin) ||
    fail 'could not hash the guest password'
unset guest_password

stage=$(mktemp -d /tmp/audit12-login-seed.XXXXXXXX)
cleanup() {
    rm -f -- "$stage/user-data" "$stage/meta-data" "$stage/network-config"
    rmdir -- "$stage" 2>/dev/null || true
}
trap cleanup EXIT
umask 077

printf '%s\n' \
    '#cloud-config' \
    'users:' \
    '  - default' \
    '  - name: audit12' \
    '    gecos: Audit12 VM test' \
    '    groups: [sudo]' \
    '    shell: /bin/bash' \
    '    lock_passwd: false' \
    "    passwd: '$password_hash'" \
    'ssh_pwauth: false' \
    'disable_root: true' \
    'chpasswd:' \
    '  expire: false' > "$stage/user-data"
unset password_hash

printf 'instance-id: audit12-login-%s\nlocal-hostname: lockdown-audit12-login\n' \
    "$(cat /proc/sys/kernel/random/uuid)" > "$stage/meta-data"
printf '%s\n' \
    'version: 2' \
    'ethernets:' \
    '  guest0:' \
    '    match:' \
    "      macaddress: '$guest_mac'" \
    '    dhcp4: true' \
    '    dhcp6: false' > "$stage/network-config"

printf 'AUDIT12 login VM: creating separate seed and copy-on-write overlay\n'
cloud-localds -N "$stage/network-config" "$seed" "$stage/user-data" "$stage/meta-data"
chown libvirt-qemu:kvm "$seed"
chmod 0440 "$seed"
qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay"
chown libvirt-qemu:kvm "$overlay"
chmod 0640 "$overlay"

printf 'AUDIT12 login VM: launching the guest\n'
if ! virt-install --connect qemu:///system \
    --name "$domain" --virt-type kvm --import --transient \
    --memory 2048 --vcpus 2 --cpu host-passthrough --osinfo generic \
    --disk "path=$overlay,format=qcow2,bus=virtio" \
    --disk "path=$seed,device=cdrom,format=raw,readonly=on" \
    --network "network=default,model=virtio,mac=$guest_mac" \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --graphics none --console pty,target.type=serial --noautoconsole; then
    fail "guest launch failed; separate seed and overlay retained for inspection"
fi

state=$(virsh -c qemu:///system domstate "$domain") ||
    fail 'transient guest disappeared after launch; assets retained for inspection'
printf 'AUDIT12 login VM: state=%s account=audit12\n' "$state"
[[ $state == running ]] || fail 'guest is not running; assets retained for inspection'
