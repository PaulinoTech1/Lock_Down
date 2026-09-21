#!/usr/bin/env bash
# cpu-security-report.sh - Render CPU vulnerability mitigation state.
#
# Read-only. Prints the microcode revision and every entry under
# /sys/devices/system/cpu/vulnerabilities/. Missing or unreadable entries
# are reported as UNKNOWN rather than failing.
#
# LOCAL: reads live sysfs on the machine it runs on.

set -euo pipefail

VULN_DIR="/sys/devices/system/cpu/vulnerabilities"
CPUINFO="/proc/cpuinfo"

echo "=== CPU security report ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Microcode revision: first occurrence in /proc/cpuinfo.
microcode="UNKNOWN"
if [[ -r "${CPUINFO}" ]]; then
    found="$(grep -m1 -i '^microcode' "${CPUINFO}" | awk -F: '{print $2}' | tr -d '[:space:]' || true)"
    if [[ -n "${found}" ]]; then
        microcode="${found}"
    fi
fi
echo "microcode: ${microcode}"
echo

echo "--- kernel cmdline (mitigation-relevant) ---"
if [[ -r /proc/cmdline ]]; then
    tr ' ' '\n' < /proc/cmdline | grep -E 'mitigations|nosmt|spectre|spec_|ibrs|ibpb|ssb|mds|l1tf|taa|mmio|srbds|gds|retbleed|bhi|vmscape' || echo "(no mitigation parameters on cmdline)"
else
    echo "UNKNOWN (/proc/cmdline unreadable)"
fi
echo

echo "--- /sys/devices/system/cpu/vulnerabilities ---"
if [[ -d "${VULN_DIR}" ]]; then
    for entry in "${VULN_DIR}"/*; do
        name="$(basename "${entry}")"
        if [[ -r "${entry}" ]]; then
            value="$(tr '\n' ' ' < "${entry}" | sed 's/ *$//')"
            printf '%-28s : %s\n' "${name}" "${value}"
        else
            printf '%-28s : UNKNOWN (unreadable)\n' "${name}"
        fi
    done
else
    echo "UNKNOWN (${VULN_DIR} absent; kernel may lack the interface)"
fi
echo

echo "--- SMT state ---"
smt_dir="/sys/devices/system/cpu/smt"
if [[ -r "${smt_dir}/active" ]]; then
    echo "smt active: $(cat "${smt_dir}/active")"
elif [[ -r "${smt_dir}/control" ]]; then
    echo "smt control: $(cat "${smt_dir}/control")"
else
    echo "UNKNOWN (smt sysfs absent)"
fi
echo
echo "=== end report ==="
