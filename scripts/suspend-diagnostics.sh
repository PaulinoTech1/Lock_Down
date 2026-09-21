#!/usr/bin/env bash
# suspend-diagnostics.sh - Gather pre/post suspend state for s2idle testing.
#
# By default this script ONLY collects state; it never suspends the machine.
# Passing --do-suspend triggers an actual suspend, but only after an explicit
# typed confirmation. There is no --yes flag, by design.
#
# LOCAL: interacts with live hardware state on the machine it runs on.

set -euo pipefail

DO_SUSPEND=0
if [[ "${1:-}" == "--do-suspend" ]]; then
    DO_SUSPEND=1
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--do-suspend]" >&2
    exit 2
fi

OUT_DIR="${SUSPEND_DIAG_DIR:-/tmp/suspend-diag}"
mkdir -p "${OUT_DIR}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

collect_state() {
    local tag="$1"
    local f="${OUT_DIR}/${stamp}-${tag}.txt"
    {
        echo "=== ${tag} @ $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
        echo "--- /sys/power/mem_sleep ---"
        cat /sys/power/mem_sleep 2>/dev/null || echo "UNREADABLE"
        echo "--- uptime ---"
        cat /proc/uptime 2>/dev/null || echo "UNREADABLE"
        echo "--- USB devices (bus/port/vid:pid; no serials) ---"
        for dev in /sys/bus/usb/devices/*; do
            [[ -f "${dev}/idVendor" ]] || continue
            vid="$(cat "${dev}/idVendor" 2>/dev/null || echo '?')"
            pid="$(cat "${dev}/idProduct" 2>/dev/null || echo '?')"
            bus="$(cat "${dev}/busnum" 2>/dev/null || echo '?')"
            port="$(cat "${dev}/devpath" 2>/dev/null || echo '?')"
            echo "bus ${bus} port ${port}: ${vid}:${pid} ($(basename "${dev}"))"
        done
        echo "--- network interfaces (names/carrier only; no MACs, IPs, SSIDs) ---"
        for iface_path in /sys/class/net/*; do
            [[ -e "${iface_path}" ]] || continue
            iface="$(basename "${iface_path}")"
            [[ "${iface}" == "lo" ]] && continue
            carrier="$(cat "${iface_path}/carrier" 2>/dev/null || echo '?')"
            oper="$(cat "${iface_path}/operstate" 2>/dev/null || echo '?')"
            echo "${iface}: operstate=${oper} carrier=${carrier}"
        done
        echo "--- NVMe namespaces ---"
        ls /dev/nvme*n1 2>/dev/null || echo "none found"
        echo "--- audio cards ---"
        cat /proc/asound/cards 2>/dev/null || echo "UNREADABLE"
        echo "--- DRM connectors ---"
        for conn in /sys/class/drm/card*-*; do
            [[ -e "${conn}/status" ]] || continue
            # Skip non-connector entries (e.g., card0-DP-1 is a connector; fine).
            echo "$(basename "${conn}"): $(cat "${conn}/status" 2>/dev/null || echo '?')"
        done
        echo "--- dmesg tail (timestamps; best effort) ---"
        dmesg 2>/dev/null | tail -30 || echo "dmesg unreadable (dmesg_restrict? run with sudo)"
    } > "${f}"
    echo "state written to ${f}"
}

if [[ "${DO_SUSPEND}" -eq 0 ]]; then
    collect_state "pre"
    echo
    echo "Pre-suspend state collected. No suspend was triggered."
    echo "Re-run with --do-suspend (with confirmation) to test, then run"
    echo "this script again after resume to collect the post state and diff."
    exit 0
fi

# --do-suspend path: mandatory typed confirmation.
echo "WARNING: this will suspend the machine to s2idle NOW."
echo "Unsaved work in other sessions will be suspended, not lost, but"
echo "a failed resume is possible on untested firmware paths."
echo "Type SUSPEND to continue:"
read -r answer
if [[ "${answer}" != "SUSPEND" ]]; then
    echo "aborted (confirmation not given)."
    exit 3
fi

mem_sleep_avail="$(cat /sys/power/mem_sleep 2>/dev/null || echo '')"
echo "firmware-advertised mem_sleep: ${mem_sleep_avail}"
# Use the firmware default (bracketed entry); never force a mode the
# firmware does not advertise.
target="$(echo "${mem_sleep_avail}" | grep -o '\[[^]]*\]' | tr -d '[]' || true)"
if [[ -z "${target}" ]]; then
    echo "could not determine default mem_sleep mode; aborting." >&2
    exit 1
fi
echo "using suspend mode: ${target}"

collect_state "pre-suspend"
echo "suspending in 5 seconds (Ctrl+C to abort)..."
sleep 5
# Record intent in the pre file, then suspend.
echo "${target}" > /sys/power/mem_sleep 2>/dev/null || {
    echo "failed to set mem_sleep to ${target}; aborting." >&2
    exit 1
}
echo "mem" > /sys/power/state || {
    echo "suspend trigger failed." >&2
    exit 1
}

# Execution resumes here after wake.
echo "resumed."
collect_state "post-resume"
echo
echo "Diff pre vs post:"
diff -u "${OUT_DIR}/${stamp}-pre-suspend.txt" "${OUT_DIR}/${stamp}-post-resume.txt" || true
echo
echo "Review the diff and dmesg before trusting this suspend path."
