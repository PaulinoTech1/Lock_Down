#!/usr/bin/env bash
# battery-report.sh - Read-only battery health/threshold report.
#
# Reports design capacity, full capacity, cycle count, health %, charge
# thresholds, charging state, and power-supply info from sysfs.
# Auto-detects the battery (BAT number); never changes thresholds.
#
# LOCAL: reads live sysfs on the machine it runs on.

set -euo pipefail

echo "=== Battery report ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Auto-detect: first /sys/class/power_supply/BAT* entry. Never assume BAT0.
bat=""
for candidate in /sys/class/power_supply/BAT*; do
    if [[ -d "${candidate}" ]]; then
        bat="${candidate}"
        break
    fi
done

if [[ -z "${bat}" ]]; then
    echo "no battery found under /sys/class/power_supply/BAT*; nothing to report."
    echo "Known power supplies:"
    ls /sys/class/power_supply/ 2>/dev/null || echo "(power_supply class absent)"
    exit 1
fi

echo "battery: $(basename "${bat}")"
echo

read_sys() {
    local f="$1"
    if [[ -r "${bat}/${f}" ]]; then
        cat "${bat}/${f}"
    else
        echo "UNKNOWN"
    fi
}

# Capacities are in uAh on most drivers; convert to mWh/Wh display via
# voltage when available, else report raw with units noted.
design_full="$(read_sys energy_full_design)"
full="$(read_sys energy_full)"
now="$(read_sys energy_now)"
design_cap_uah="$(read_sys charge_full_design)"
cap_uah="$(read_sys charge_full)"
now_uah="$(read_sys charge_now)"

echo "--- capacity ---"
if [[ "${design_full}" != "UNKNOWN" && "${full}" != "UNKNOWN" ]]; then
    # energy_* in uWh.
    design_wh="$(awk "BEGIN {printf \"%.2f\", ${design_full}/1000000}")"
    full_wh="$(awk "BEGIN {printf \"%.2f\", ${full}/1000000}")"
    health="$(awk "BEGIN {printf \"%.2f\", 100*${full}/${design_full}}")"
    echo "design (energy_full_design): ${design_wh} Wh"
    echo "full   (energy_full):        ${full_wh} Wh"
    echo "health: ${health}%"
    if [[ "${now}" != "UNKNOWN" ]]; then
        now_wh="$(awk "BEGIN {printf \"%.2f\", ${now}/1000000}")"
        pct="$(awk "BEGIN {printf \"%.1f\", 100*${now}/${full}}")"
        echo "current charge: ${now_wh} Wh (${pct}% of full)"
    fi
elif [[ "${design_cap_uah}" != "UNKNOWN" && "${cap_uah}" != "UNKNOWN" ]]; then
    # charge_* in uAh; health is still a valid ratio.
    health="$(awk "BEGIN {printf \"%.2f\", 100*${cap_uah}/${design_cap_uah}}")"
    echo "design (charge_full_design): ${design_cap_uah} uAh"
    echo "full   (charge_full):        ${cap_uah} uAh"
    echo "health: ${health}%"
    if [[ "${now_uah}" != "UNKNOWN" ]]; then
        pct="$(awk "BEGIN {printf \"%.1f\", 100*${now_uah}/${cap_uah}}")"
        echo "current charge: ${now_uah} uAh (${pct}% of full)"
    fi
else
    echo "capacity: UNKNOWN (neither energy_* nor charge_* readable)"
fi
echo

echo "--- wear ---"
echo "cycle_count: $(read_sys cycle_count)"
echo

echo "--- charge thresholds (read-only; never modified by this script) ---"
echo "charge_control_start_threshold: $(read_sys charge_control_start_threshold)"
echo "charge_control_end_threshold:   $(read_sys charge_control_end_threshold)"
echo "(expected per project baseline: 75/80; this script reports, never sets)"
echo

echo "--- state ---"
echo "status:       $(read_sys status)"
echo "capacity pct: $(read_sys capacity)"
if [[ -r "${bat}/power_now" ]]; then
    pw="$(cat "${bat}/power_now")"
    echo "power_now: ${pw} uW"
fi
echo

echo "--- power supplies ---"
for ps in /sys/class/power_supply/*; do
    [[ -d "${ps}" ]] || continue
    name="$(basename "${ps}")"
    type="$(cat "${ps}/type" 2>/dev/null || echo UNKNOWN)"
    online="$(cat "${ps}/online" 2>/dev/null || echo '-')"
    echo "${name}: type=${type} online=${online}"
done
echo
echo "Note: thresholds were read, never changed."
echo "=== end report ==="
