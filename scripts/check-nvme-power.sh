#!/usr/bin/env bash
# check-nvme-power.sh - Read-only NVMe power/health report.
#
# Reports model, firmware, supported power states, APST status, current
# policy where observable, controller temperature, unsafe shutdowns, and
# media/data integrity errors from the SMART log.
#
# Read-only by construction: never writes feature values, never formats,
# never sanitizes. Auto-detects the NVMe device (never assumes /dev/nvme0n1)
# and handles absence gracefully.
#
# LOCAL: reads live device state on the machine it runs on.

set -euo pipefail

fail=0

note_fail() { echo "FAIL: $1"; fail=1; }
note_info() { echo "$1"; }

echo "=== NVMe power/health report ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Auto-detect NVMe namespaces: /dev/nvme<n>n<m>, pick the first namespace
# of each controller. Never assume /dev/nvme0n1.
mapfile -t nvme_devs < <(ls /dev/nvme*n1 2>/dev/null || true)
if [[ "${#nvme_devs[@]}" -eq 0 ]]; then
    note_fail "no NVMe namespace devices found under /dev (no /dev/nvme*n1)"
    echo "Nothing to report; no state was changed."
    exit 1
fi

note_info "detected NVMe namespaces: ${nvme_devs[*]}"
echo

have_nvme_cli=0
if command -v nvme >/dev/null 2>&1; then
    have_nvme_cli=1
fi

for ns in "${nvme_devs[@]}"; do
    # Controller device: strip the trailing 'n<digits>' namespace suffix.
    ctrl="$(echo "${ns}" | sed -E 's/n[0-9]+$//')"
    # Sysfs for model/firmware lives under the namespace block device:
    # /sys/block/nvme0n1/device -> controller dir with model/firmware_rev.
    ns_base="$(basename "${ns}")"
    sysdev="/sys/block/${ns_base}/device"
    echo "--- namespace ${ns} (controller ${ctrl}) ---"

    # Model / firmware from sysfs (no nvme-cli dependency).
    if [[ -r "${sysdev}/model" ]]; then
        note_info "model:    $(tr -s ' ' < "${sysdev}/model" | sed 's/^ *//;s/ *$//')"
    else
        note_info "model:    UNKNOWN (sysfs unreadable)"
    fi
    if [[ -r "${sysdev}/firmware_rev" ]]; then
        note_info "firmware: $(tr -d '[:space:]' < "${sysdev}/firmware_rev")"
    else
        note_info "firmware: UNKNOWN (sysfs unreadable)"
    fi

    # Power states and APST via nvme-cli when available.
    if [[ "${have_nvme_cli}" -eq 1 ]]; then
        echo "-- id-ctrl power state descriptors --"
        if id_ctrl="$(nvme id-ctrl "${ctrl}" 2>/dev/null)"; then
            echo "${id_ctrl}" | grep -A40 'ps *0 :' | head -45 || true
        else
            note_info "nvme id-ctrl failed (permissions? try with sudo)"
        fi
        echo "-- APST (feature 0x0c) --"
        if apst="$(nvme get-feature "${ctrl}" -f 0x0c 2>/dev/null)"; then
            echo "${apst}" | grep -iE 'autonomous|value' || echo "${apst}"
        else
            note_info "APST feature read failed (permissions? try with sudo)"
        fi
    else
        note_info "nvme-cli not installed: power-state/APST detail unavailable (install nvme-cli for full report)"
    fi

    # sysfs power policy where observable.
    echo "-- power policy (sysfs) --"
    if [[ -d "${sysdev}/power" ]]; then
        for f in control runtime_status; do
            if [[ -r "${sysdev}/power/${f}" ]]; then
                note_info "power/${f}: $(cat "${sysdev}/power/${f}")"
            fi
        done
    else
        note_info "device power sysfs absent"
    fi

    # SMART log: temperature, unsafe shutdowns, media/data integrity errors.
    echo "-- SMART log --"
    if [[ "${have_nvme_cli}" -eq 1 ]]; then
        if smart="$(nvme smart-log "${ctrl}" 2>/dev/null)"; then
            echo "${smart}" | grep -iE 'temperature|unsafe_shutdowns|media.*error|data.*integr|power_cycles|power_on_hours|critical_warning' || echo "${smart}"
        else
            note_info "smart-log read failed (permissions? try with sudo)"
        fi
    else
        # Fallback: hwmon temperature if exposed.
        note_info "nvme-cli absent; SMART detail unavailable"
    fi
    echo
done

echo "Note: this script never writes NVMe feature values."
echo "=== end report ==="
exit "${fail}"
