#!/usr/bin/env bash
# check-intel-display.sh - Read-only Intel i915 display power state report.
#
# Reports i915 module parameters in effect, FBC/PSR status, runtime PM
# state for the GPU, and firmware load status where readable.
# Read-only: never writes module parameters or sysfs values.
#
# LOCAL: reads live sysfs/debugfs on the machine it runs on.

set -euo pipefail

echo "=== Intel display power report ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Find the Intel GPU PCI device (8086:46a8 on this machine, but do not
# hard-code: discover any Intel VGA/display device).
gpu_bdf=""
for dev in /sys/bus/pci/devices/*; do
    [[ -e "${dev}/vendor" ]] || continue
    vendor="$(cat "${dev}/vendor" 2>/dev/null || echo '')"
    class="$(cat "${dev}/class" 2>/dev/null || echo '')"
    if [[ "${vendor}" == "0x8086" && "${class}" == 0x03* ]]; then
        gpu_bdf="$(basename "${dev}")"
        break
    fi
done

if [[ -z "${gpu_bdf}" ]]; then
    echo "no Intel display-class PCI device found; nothing to report."
    exit 1
fi
echo "GPU PCI device: ${gpu_bdf}"
gpu_sys="/sys/bus/pci/devices/${gpu_bdf}"
echo

echo "--- driver binding ---"
if [[ -L "${gpu_sys}/driver" ]]; then
    echo "driver: $(basename "$(readlink "${gpu_sys}/driver")")"
else
    echo "driver: UNKNOWN (no driver symlink)"
fi
echo

echo "--- i915 module parameters ---"
modparam_dir="/sys/module/i915/parameters"
if [[ -d "${modparam_dir}" ]]; then
    for p in enable_guc enable_huc enable_fbc enable_psr enable_dc; do
        if [[ -r "${modparam_dir}/${p}" ]]; then
            echo "${p}: $(cat "${modparam_dir}/${p}")"
        else
            echo "${p}: UNKNOWN (parameter absent/unreadable)"
        fi
    done
else
    echo "UNKNOWN (i915 module parameters absent; driver may not be loaded)"
fi
echo

echo "--- FBC / PSR status (debugfs/sysfs where readable) ---"
# debugfs i915 display info; path varies by kernel, try candidates.
found_status=0
for candidate in \
    /sys/kernel/debug/dri/0/i915_display_info \
    /sys/kernel/debug/dri/0/i915_fbc_status; do
    if [[ -r "${candidate}" ]]; then
        echo "## ${candidate} (FBC/PSR-relevant lines) ##"
        grep -iE 'fbc|psr' "${candidate}" | head -20 || true
        found_status=1
    fi
done
if [[ "${found_status}" -eq 0 ]]; then
    echo "no readable i915 display debugfs status (debugfs may be restricted or unmounted)"
fi
echo

echo "--- runtime PM ---"
if [[ -r "${gpu_sys}/power/control" ]]; then
    echo "power/control: $(cat "${gpu_sys}/power/control")"
else
    echo "power/control: UNKNOWN"
fi
if [[ -r "${gpu_sys}/power/runtime_status" ]]; then
    echo "power/runtime_status: $(cat "${gpu_sys}/power/runtime_status")"
else
    echo "power/runtime_status: UNKNOWN"
fi
echo

echo "--- firmware load status (dmesg, best effort) ---"
if dmesg_out="$(dmesg 2>/dev/null | grep -iE 'i915.*(dmc|guc|huc|firmware)' | tail -15 || true)"; then
    if [[ -n "${dmesg_out}" ]]; then
        echo "${dmesg_out}"
    else
        echo "dmesg readable but no i915 firmware lines found"
    fi
else
    echo "dmesg unreadable (likely kernel.dmesg_restrict=1); firmware status unverifiable this way"
fi
echo

echo "--- panel (drm connector info, best effort) ---"
for conn in /sys/class/drm/card*-eDP-*; do
    [[ -e "${conn}" ]] || continue
    echo "connector: $(basename "${conn}")"
    [[ -r "${conn}/status" ]] && echo "  status: $(cat "${conn}/status")"
    [[ -r "${conn}/modes" ]] && echo "  preferred mode: $(head -1 "${conn}/modes")"
done
echo
echo "=== end report ==="
