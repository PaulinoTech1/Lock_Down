#!/usr/bin/env bash
# hardware-audit.sh - Read-only hardware gatherer for kernel config refinement.
#
# Collects: CPU, PCI devices, USB devices, loaded modules, firmware
# versions, graphics, audio, input, TPM caps, NVMe model/fw/power states,
# battery, /sys/power/mem_sleep, Secure Boot state, IOMMU state,
# virtualization flags.
#
# MUST NOT collect: disk serials, MAC addresses, public IPs, Wi-Fi SSIDs,
# usernames, home directory names, machine IDs, TPM EKs, YubiKey serials.
# Where a tool would print a forbidden field, it is filtered or the tool
# is not run.
#
# Output is intended to be safe to paste into a public issue AFTER MANUAL
# REVIEW. A reminder is printed at the end. Review before pasting anyway:
# filters are best-effort, not a guarantee.
#
# LOCAL: reads live hardware state on the machine it runs on.

set -euo pipefail

echo "=== hardware audit ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "kernel: $(uname -r)"
echo

echo "--- CPU ---"
if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -iE 'model name|architecture|cpu\(s\)|thread|core|socket|flags' | head -10
    echo "virtualization flags present:"
    lscpu | grep -oiE 'vmx|svm|ept|vpid' | sort -u || echo "(none detected)"
else
    grep -m1 'model name' /proc/cpuinfo || echo "lscpu absent and /proc/cpuinfo unreadable"
fi
echo

echo "--- microcode ---"
grep -m1 -i '^microcode' /proc/cpuinfo 2>/dev/null || echo "UNKNOWN"
echo

echo "--- PCI devices (vendor:device + class; no serials) ---"
if command -v lspci >/dev/null 2>&1; then
    # -nn gives [vvvv:dddd]; -k adds driver. No serial numbers in lspci -nn.
    lspci -nnk 2>/dev/null || lspci -nn 2>/dev/null || echo "lspci failed"
else
    echo "lspci not installed; PCI summary unavailable"
fi
echo

echo "--- USB devices (vid:pid + bus/port; no serials) ---"
for dev in /sys/bus/usb/devices/*; do
    [[ -f "${dev}/idVendor" ]] || continue
    vid="$(cat "${dev}/idVendor" 2>/dev/null || echo '?')"
    pid="$(cat "${dev}/idProduct" 2>/dev/null || echo '?')"
    bus="$(cat "${dev}/busnum" 2>/dev/null || echo '?')"
    port="$(cat "${dev}/devpath" 2>/dev/null || echo '?')"
    manufacturer="$(cat "${dev}/manufacturer" 2>/dev/null || echo '')"
    product="$(cat "${dev}/product" 2>/dev/null || echo '')"
    # Deliberately NOT reading ${dev}/serial.
    echo "bus ${bus} port ${port}: ${vid}:${pid} ${manufacturer} ${product}"
done
echo

echo "--- loaded modules ---"
if [[ -r /proc/modules ]]; then
    awk '{print $1}' /proc/modules | sort | tr '\n' ' '
    echo
else
    echo "UNKNOWN (/proc/modules unreadable)"
fi
echo

echo "--- graphics ---"
for dev in /sys/bus/pci/devices/*; do
    [[ -f "${dev}/vendor" ]] || continue
    class="$(cat "${dev}/class" 2>/dev/null || echo '')"
    if [[ "${class}" == 0x03* ]]; then
        vendor="$(cat "${dev}/vendor" 2>/dev/null || echo '?')"
        device="$(cat "${dev}/device" 2>/dev/null || echo '?')"
        driver="none"
        [[ -L "${dev}/driver" ]] && driver="$(basename "$(readlink "${dev}/driver")")"
        echo "$(basename "${dev}"): ${vendor}:${device} driver=${driver}"
    fi
done
echo

echo "--- audio ---"
cat /proc/asound/cards 2>/dev/null || echo "no ALSA cards visible"
echo

echo "--- input ---"
if [[ -r /proc/bus/input/devices ]]; then
    grep -E '^(N|H):' /proc/bus/input/devices | head -40
else
    echo "UNKNOWN"
fi
echo

echo "--- TPM ---"
if [[ -d /sys/class/tpm/tpm0 ]]; then
    echo "tpm0 present"
    if command -v tpm2_getcap >/dev/null 2>&1; then
        echo "tpm2_getcap properties-fixed (no EK, no secrets):"
        # properties-fixed only; NEVER tpm2_getekcertificate / EK handles.
        tpm2_getcap properties-fixed 2>/dev/null | head -20 || echo "(tpm2_getcap failed; need privileges?)"
    else
        echo "tpm2-tools not installed; TPM caps unavailable"
    fi
    if [[ -r /sys/class/tpm/tpm0/device/firmware_version ]]; then
        echo "firmware_version: $(cat /sys/class/tpm/tpm0/device/firmware_version)"
    fi
else
    echo "no TPM device node found"
fi
echo

echo "--- NVMe (model/fw/power states; no serials) ---"
for ns in /dev/nvme*n1; do
    [[ -e "${ns}" ]] || continue
    ns_base="$(basename "${ns}")"
    sysdev="/sys/block/${ns_base}/device"
    model="$(tr -s ' ' < "${sysdev}/model" 2>/dev/null | sed 's/^ *//;s/ *$//' || echo UNKNOWN)"
    fw="$(tr -d '[:space:]' < "${sysdev}/firmware_rev" 2>/dev/null || echo UNKNOWN)"
    # Deliberately NOT reading ${sysdev}/serial.
    echo "${ns}: model=${model} firmware=${fw}"
    if command -v nvme >/dev/null 2>&1; then
        ctrl="$(echo "${ns}" | sed -E 's/n[0-9]+$//')"
        nvme get-feature "${ctrl}" -f 0x0c 2>/dev/null | grep -iE 'autonomous|value' || echo "  APST: unreadable (need sudo?)"
    fi
done
echo

echo "--- battery ---"
for bat in /sys/class/power_supply/BAT*; do
    [[ -d "${bat}" ]] || continue
    echo "$(basename "${bat}"):"
    for f in energy_full_design energy_full cycle_count status charge_control_start_threshold charge_control_end_threshold; do
        [[ -r "${bat}/${f}" ]] && echo "  ${f}: $(cat "${bat}/${f}")"
    done
done
echo

echo "--- suspend modes ---"
cat /sys/power/mem_sleep 2>/dev/null || echo "UNREADABLE"
echo

echo "--- Secure Boot state ---"
if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null || echo "(mokutil --sb-state failed)"
else
    if [[ -d /sys/firmware/efi ]]; then
        echo "EFI boot; SecureBoot variable:"
        # efivarfs read without efi-readvar; best effort.
        od -An -tu1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tail -1 || echo "UNREADABLE"
    else
        echo "not an EFI boot (no /sys/firmware/efi)"
    fi
fi
echo

echo "--- IOMMU state ---"
if [[ -r /proc/cmdline ]]; then
    echo "cmdline iommu params: $(tr ' ' '\n' < /proc/cmdline | grep -E 'iommu|dmar' || echo '(none)')"
fi
if [[ -d /sys/kernel/iommu_groups ]]; then
    count="$(ls /sys/kernel/iommu_groups | wc -l)"
    echo "iommu_groups present: ${count} groups"
else
    echo "iommu_groups absent"
fi
echo

echo "--- firmware versions (fwupd, best effort; no flashing) ---"
if command -v fwupdmgr >/dev/null 2>&1; then
    fwupdmgr get-devices 2>/dev/null | grep -iE 'device|guid|version|vendor' | head -40 || echo "(fwupdmgr get-devices failed)"
else
    echo "fwupdmgr not installed"
fi
echo

echo "=== end audit ==="
echo
echo "REMINDER: review this output manually before pasting it anywhere public."
echo "It is filtered to exclude disk serials, MACs, IPs, SSIDs, usernames,"
echo "home paths, machine IDs, TPM EKs, and YubiKey serials, but filters are"
echo "best-effort. If you spot anything identifying, redact it by hand."
