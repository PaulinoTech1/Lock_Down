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
CHECK_ONLY=0
if [[ "${1:-}" == "--do-suspend" ]]; then
    DO_SUSPEND=1
elif [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=1
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--check|--do-suspend]" >&2
    exit 2
fi

[[ $# -le 1 ]] || exit 2
base="${SUSPEND_EVIDENCE_ROOT:-}"
[[ -z "$base" || "$DO_SUSPEND" == 0 ]] || { echo 'FAIL offline evidence cannot authorize suspend'; exit 1; }
umask 077
# shellcheck source=scripts/safe-directory.sh
source "$(dirname "${BASH_SOURCE[0]}")/safe-directory.sh"
if [[ -n "${SUSPEND_DIAG_DIR:-}" ]]; then
    safe_directory "$SUSPEND_DIAG_DIR" || { echo 'FAIL unsafe diagnostic parent'; exit 1; }
    parent="$SUSPEND_DIAG_DIR"
else
    parent=/tmp
fi
check_s2idle() {
    local modes
    modes="$(cat "$base/sys/power/mem_sleep" 2>/dev/null)" || { echo 'UNKNOWN mem_sleep unreadable'; return 3; }
    [[ "$(grep -o '\[[^]]*\]' <<< "$modes")" == '[s2idle]' ]] || { echo 'FAIL default sleep mode is not s2idle'; return 1; }
    echo 'PASS s2idle is the selected mode (not a suspend test)'
}
if [[ "$CHECK_ONLY" == 1 ]]; then check_s2idle; exit $?; fi
OUT_DIR="$(mktemp -d "$parent/lockdown-suspend.XXXXXXXX")"
safe_directory "$OUT_DIR" || { echo 'FAIL unsafe diagnostic directory'; exit 1; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

collect_state() {
    local tag="$1"
    local f="${OUT_DIR}/${stamp}-${tag}.txt"
    {
        echo "=== ${tag} @ $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
        echo "--- /sys/power/mem_sleep ---"
        cat "$base/sys/power/mem_sleep" 2>/dev/null || echo "UNREADABLE"
        echo "--- uptime ---"
        cat "$base/proc/uptime" 2>/dev/null || echo "UNREADABLE"
        echo "--- USB devices (bus/port/vid:pid; no serials) ---"
        for dev in "$base"/sys/bus/usb/devices/*; do
            [[ -f "${dev}/idVendor" ]] || continue
            vid="$(cat "${dev}/idVendor" 2>/dev/null || echo '?')"
            pid="$(cat "${dev}/idProduct" 2>/dev/null || echo '?')"
            bus="$(cat "${dev}/busnum" 2>/dev/null || echo '?')"
            port="$(cat "${dev}/devpath" 2>/dev/null || echo '?')"
            echo "bus ${bus} port ${port}: ${vid}:${pid} ($(basename "${dev}"))"
        done
        echo "--- network interfaces (names/carrier only; no MACs, IPs, SSIDs) ---"
        for iface_path in "$base"/sys/class/net/*; do
            [[ -e "${iface_path}" ]] || continue
            iface="$(basename "${iface_path}")"
            [[ "${iface}" == "lo" ]] && continue
            carrier="$(cat "${iface_path}/carrier" 2>/dev/null || echo '?')"
            oper="$(cat "${iface_path}/operstate" 2>/dev/null || echo '?')"
            echo "${iface}: operstate=${oper} carrier=${carrier}"
        done
        echo "--- NVMe namespaces ---"
        ls "$base"/dev/nvme*n1 2>/dev/null || echo "none found"
        echo "--- audio cards ---"
        cat "$base/proc/asound/cards" 2>/dev/null || echo "UNREADABLE"
        echo "--- DRM connectors ---"
        for conn in "$base"/sys/class/drm/card*-*; do
            [[ -e "${conn}/status" ]] || continue
            # Skip non-connector entries (e.g., card0-DP-1 is a connector; fine).
            echo "$(basename "${conn}"): $(cat "${conn}/status" 2>/dev/null || echo '?')"
        done
        echo '--- raw dmesg omitted: may contain identifiers or secrets ---'
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
check_s2idle
echo "WARNING: confirmation below authorizes an s2idle suspend."
echo "Unsaved work in other sessions will be suspended, not lost, but"
echo "a failed resume is possible on untested firmware paths."
echo "Type SUSPEND to continue:"
read -r answer
if [[ "${answer}" != "SUSPEND" ]]; then
    echo "aborted (confirmation not given)."
    exit 3
fi

check_s2idle
target=s2idle

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
