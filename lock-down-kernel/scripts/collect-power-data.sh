#!/usr/bin/env bash
set -u

usage() {
    cat <<'EOF'
Usage: collect-power-data.sh [--output DIR] [--duration SECONDS] [--turbostat]

Collect read-only power, idle, interrupt, and runtime-policy observations.
No sysfs policy is changed and the machine is never suspended.
EOF
}

OUTPUT=""
DURATION=10
RUN_TURBOSTAT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) OUTPUT="${2:?--output requires DIR}"; shift 2 ;;
        --duration) DURATION="${2:?--duration requires SECONDS}"; shift 2 ;;
        --turbostat) RUN_TURBOSTAT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$DURATION" in ''|*[!0-9]*) echo "ERROR: duration must be an integer" >&2; exit 2 ;; esac
[ "$DURATION" -gt 0 ] || { echo "ERROR: duration must be positive" >&2; exit 2; }

if [ -z "$OUTPUT" ]; then
    OUTPUT="${TMPDIR:-/tmp}/lock-down-power-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUTPUT"

capture() {
    local name="$1"
    shift
    {
        echo "# command: $*"
        echo "# collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "$@" 2>&1 || echo "UNAVAILABLE: exit=$?"
    } >"$OUTPUT/$name"
}

capture uname.txt uname -a
capture cmdline.txt cat /proc/cmdline
capture cpuidle-driver.txt cat /sys/devices/system/cpu/cpuidle/current_driver
capture cpuidle-governor.txt cat /sys/devices/system/cpu/cpuidle/current_governor
capture pstate-status.txt cat /sys/devices/system/cpu/intel_pstate/status
capture scaling-drivers.txt sh -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_driver; do [ -r "$f" ] && printf "%s: " "$f" && cat "$f"; done'
capture energy-preferences.txt sh -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_{available_preferences,current,percentage}; do [ -r "$f" ] && printf "%s: " "$f" && cat "$f"; done'
capture cpuidle-states.txt sh -c 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/*; do [ -r "$f" ] && case "$f" in */name|*/usage|*/time|*/disable|*/latency|*/residency) printf "%s: " "$f"; cat "$f";; esac; done'
capture interrupts.txt cat /proc/interrupts
capture proc-stat.txt cat /proc/stat
capture memory.txt cat /proc/meminfo
capture power-supplies.txt sh -c 'for d in /sys/class/power_supply/*; do [ -d "$d" ] || continue; echo "[$d]"; for f in type status capacity power_now energy_now energy_full energy_full_design; do [ -r "$d/$f" ] && printf "%s=" "$f" && cat "$d/$f"; done; done'
capture nvme-runtime-pm.txt sh -c 'for d in /sys/block/nvme*/device/power; do [ -d "$d" ] || continue; echo "[$d]"; for f in control runtime_status runtime_active_time runtime_suspended_time; do [ -r "$d/$f" ] && printf "%s=" "$f" && cat "$d/$f"; done; done'

if [ "$RUN_TURBOSTAT" -eq 1 ]; then
    if command -v turbostat >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        timeout "$((DURATION + 5))" turbostat --quiet --interval 1 --num_iterations "$DURATION" >"$OUTPUT/turbostat.txt" 2>&1 || true
    else
        echo "UNAVAILABLE: turbostat or timeout is not installed" >"$OUTPUT/turbostat.txt"
    fi
fi

cat >"$OUTPUT/README.txt" <<EOF
Lock_Down power data
Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Duration: ${DURATION}s

This collection is read-only. It does not alter governors, runtime-PM policy,
USB autosuspend, NVMe APST, power profiles, kernel parameters, or suspend state.
Compare equivalent collections on stock and candidate kernels. Do not infer
battery improvement from configuration alone.
EOF

echo "power data written to $OUTPUT"
