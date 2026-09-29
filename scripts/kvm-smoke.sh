#!/usr/bin/env bash
# Two identical offline KVM boots of the currently running kernel.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
release="$(uname -r)"
kernel="/boot/vmlinuz-$release"
busybox=/usr/bin/busybox
qemu=/usr/bin/qemu-system-x86_64
init="$repo_dir/tests/fixtures/kvm-smoke-init"
manifest="$repo_dir/tests/fixtures/kvm-smoke-initramfs.list"
generator_source="$repo_dir/linux-6.18.53/usr/gen_init_cpio.c"

fail() {
    printf 'KVM smoke: FAIL: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 0 ] || fail 'this fixed guest test takes no arguments'
[ "$EUID" -ne 0 ] || fail 'run this test as an unprivileged user'

for tool in cc readelf sha256sum timeout; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done
[ -r /dev/kvm ] && [ -w /dev/kvm ] || fail 'current user cannot access /dev/kvm'
[ -r "$kernel" ] || fail "missing running-kernel image: $kernel"
[ -r "$busybox" ] || fail "missing guest busybox: $busybox"
[ -x "$qemu" ] || fail "missing QEMU: $qemu"
if readelf -l -- "$busybox" | grep -q INTERP; then
    fail 'busybox must be statically linked for this initramfs'
fi
[ -r "$init" ] && [ -r "$manifest" ] && [ -r "$generator_source" ] ||
    fail 'guest fixture or gen_init_cpio source is missing'

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lockdown-kvm-smoke.XXXXXX")"
cleanup() {
    rm -f -- "$tmp_dir/gen_init_cpio" "$tmp_dir/initramfs.cpio" \
        "$tmp_dir/run-1.log" "$tmp_dir/run-2.log"
    rmdir -- "$tmp_dir"
}
trap cleanup EXIT

cc -O2 -o "$tmp_dir/gen_init_cpio" "$generator_source"
export LOCKDOWN_KVM_BUSYBOX="$busybox"
export LOCKDOWN_KVM_INIT="$init"
"$tmp_dir/gen_init_cpio" -t 0 -o "$tmp_dir/initramfs.cpio" "$manifest"

read -r kernel_hash _ < <(sha256sum -- "$kernel")
read -r busybox_hash _ < <(sha256sum -- "$busybox")
read -r initramfs_hash _ < <(sha256sum -- "$tmp_dir/initramfs.cpio")
printf 'host_release=%s\nkernel_sha256=%s\nbusybox_sha256=%s\ninitramfs_sha256=%s\n' \
    "$release" "$kernel_hash" "$busybox_hash" "$initramfs_hash"

marker="LOCKDOWN_KVM_SMOKE_OK release=$release"
for run in 1 2; do
    log="$tmp_dir/run-$run.log"
    if ! timeout --signal=TERM --kill-after=2s 30s \
        "$qemu" \
        -accel kvm -cpu host -m 512 -smp 2 \
        -nodefaults -nic none -display none -serial stdio -monitor none \
        -no-reboot \
        -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny \
        -kernel "$kernel" -initrd "$tmp_dir/initramfs.cpio" \
        -append 'console=ttyS0 rdinit=/init quiet loglevel=4' >"$log" 2>&1; then
        tail -n 30 -- "$log" >&2
        fail "run $run: QEMU failed or timed out"
    fi
    if [ "$(grep -Fc -- "$marker" "$log" || true)" != 1 ] ||
        ! grep -Fq -- 'reboot: Power down' "$log" ||
        grep -Fq -- 'LOCKDOWN_KVM_SMOKE_POWER_OFF_FAILED' "$log"; then
        tail -n 30 -- "$log" >&2
        fail "run $run: guest marker or clean power-off missing"
    fi
    printf 'PASS run=%s release=%s\n' "$run" "$release"
done

echo 'KVM smoke: PASS (2/2)'
