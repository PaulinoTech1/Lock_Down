#!/usr/bin/env bash
# Read-only evidence collection. This does not authorize or schedule a reboot.
set -euo pipefail

if (( EUID != 0 )); then
    echo 'Run with sudo: initramfs and generated GRUB configuration are root-readable.' >&2
    exit 1
fi

release=6.18.53-lockdown-t14g3-audit3
initrd=/boot/initrd.img-$release
grub_config=/boot/grub/grub.cfg
for required in "$initrd" "$grub_config" /etc/crypttab; do
    if [[ ! -r "$required" ]]; then
        echo "Cannot read required evidence: $required" >&2
        exit 1
    fi
done

printf '\n=== Running and installed kernels ===\n'
uname -r
dpkg-query -W -f='${Package} ${Version} ${Status}\n' \
    "linux-image-$release" linux-image-7.0.0-31-generic linux-image-7.0.0-34-generic
printf '\n=== Candidate initramfs checksum ===\n'
sha256sum "$initrd"
printf '\n=== Dracut modules ===\n'
lsinitrd -m "$initrd"
printf '\n=== Relevant initramfs paths (listing only; no key contents) ===\n'
listing=$(lsinitrd "$initrd")
printf '%s\n' "$listing" | grep -Ei \
    'crypt|cmdline|lvm|dmsetup|rootfs|microcode|GenuineIntel|firmware/(i915|mediatek|intel/sof|intel/avs)|sof.*tplg|modules\.builtin' || true
printf '\n=== Host root and crypttab ===\n'
findmnt -no SOURCE,FSTYPE /
cat /etc/crypttab
printf '\n=== Candidate crypttab and generated command-line files ===\n'
# Only these text configuration paths may be read; never print keyfile contents.
while IFS= read -r entry; do
    printf '\n--- %s ---\n' "$entry"
    lsinitrd -f "$entry" "$initrd"
done < <(printf '%s\n' "$listing" | awk \
    '$NF == "etc/crypttab" || $NF ~ /^etc\/cmdline\.d\/[A-Za-z0-9_.-]+\.conf$/ {print $NF}')
printf '\n=== GRUB defaults and generated selection/menu/kernel lines ===\n'
grep -HnE '^[[:space:]]*GRUB_(DEFAULT|SAVEDEFAULT|TIMEOUT|TIMEOUT_STYLE)=' \
    /etc/default/grub /etc/default/grub.d/*.cfg || true
grep -nE 'set default=|saved_entry|next_entry|^[[:space:]]*(menuentry|submenu|linux|linuxefi|initrd|initrdefi)[[:space:]]' "$grub_config"
printf '\n=== GRUB environment (read only; note any hostdisk error) ===\n'
grub-editenv /boot/grub/grubenv list || true
printf '\nEvidence collected; no boot selection, swap setting, or file was changed.\n'
