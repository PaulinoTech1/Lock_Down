#!/usr/bin/env bash
# check-iommu.sh - Verify IOMMU / VT-d / interrupt-remapping state.
#
# Read-only. Inspects the kernel command line, dmesg (tolerating unreadable
# dmesg under dmesg_restrict), interrupt-remapping status, and the IOMMU
# group layout from sysfs. Flags devices that appear to lack isolation.
#
# This script NEVER claims DMA isolation merely because an IOMMU exists:
# it reports capability and active enforcement separately, and exits
# non-zero when enforcement cannot be confirmed.
#
# LOCAL: reads live kernel state on the machine it runs on.

set -euo pipefail

fail=0
warn=0

note_fail() { echo "FAIL: $1"; fail=1; }
note_warn() { echo "WARN: $1"; warn=1; }
note_ok()   { echo "OK:   $1"; }

echo "=== IOMMU / VT-d check ==="
echo "date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# 1. Kernel command line: look for IOMMU enablement parameters.
echo "--- /proc/cmdline ---"
cmdline=""
if [[ -r /proc/cmdline ]]; then
    cmdline="$(cat /proc/cmdline)"
    echo "${cmdline}"
    if echo "${cmdline}" | grep -qw 'intel_iommu=on'; then
        note_ok "intel_iommu=on present on cmdline"
    elif echo "${cmdline}" | grep -qE 'intel_iommu=[^ ]*|iommu=[^ ]*'; then
        note_warn "iommu-related parameter present but not intel_iommu=on; verify semantics"
    else
        note_warn "no intel_iommu/iommu parameter on cmdline (may rely on defaults)"
    fi
else
    note_warn "/proc/cmdline unreadable"
fi
echo

# 2. dmesg: DMAR / IOMMU init lines. dmesg may be restricted
# (kernel.dmesg_restrict=1); handle that gracefully.
echo "--- dmesg: DMAR/IOMMU ---"
dmesg_out=""
if dmesg_out="$(dmesg 2>/dev/null | grep -iE 'dmar|iommu' || true)"; then
    if [[ -z "${dmesg_out}" ]]; then
        note_warn "dmesg readable but no DMAR/IOMMU lines found"
    else
        echo "${dmesg_out}"
        if echo "${dmesg_out}" | grep -qiE 'IOMMU.*(enabled|found)|DMAR.*(enabled|found)|dmar.*initialized'; then
            note_ok "dmesg shows IOMMU/DMAR initialization"
        else
            note_warn "dmesg DMAR/IOMMU lines present but no clear 'enabled' marker; review manually"
        fi
    fi
else
    note_warn "dmesg unreadable (likely kernel.dmesg_restrict=1); skipping dmesg evidence"
fi
echo

# 3. Interrupt remapping status.
echo "--- interrupt remapping ---"
if [[ -r /sys/kernel/iommu_groups ]]; then
    note_ok "/sys/kernel/iommu_groups present"
else
    note_warn "/sys/kernel/iommu_groups absent"
fi
# Best-effort: check dmesg again only if we could read it.
if [[ -n "${dmesg_out}" ]]; then
    if echo "${dmesg_out}" | grep -qi 'interrupt remapping.*enabled\|IR.*enabled'; then
        note_ok "interrupt remapping reported enabled"
    elif echo "${dmesg_out}" | grep -qi 'interrupt remapping'; then
        note_warn "interrupt remapping mentioned but state unclear; review manually"
    else
        note_warn "no interrupt-remapping evidence in dmesg output"
    fi
else
    note_warn "interrupt-remapping state unverifiable (no dmesg access)"
fi
echo

# 4. IOMMU group layout from sysfs.
echo "--- IOMMU groups ---"
group_base="/sys/kernel/iommu_groups"
if [[ -d "${group_base}" ]]; then
    group_count=0
    for group in "${group_base}"/*; do
        [[ -d "${group}" ]] || continue
        group_count=$((group_count + 1))
        gid="$(basename "${group}")"
        echo "group ${gid}:"
        dev_count=0
        for devlink in "${group}"/devices/*; do
            [[ -e "${devlink}" ]] || continue
            dev_count=$((dev_count + 1))
            bdf="$(basename "${devlink}")"
            # lspci may not exist; use sysfs class/vendor/device when possible.
            class="$(cat "${devlink}/class" 2>/dev/null || echo '?')"
            vendor="$(cat "${devlink}/vendor" 2>/dev/null || echo '?')"
            device="$(cat "${devlink}/device" 2>/dev/null || echo '?')"
            echo "  ${bdf} [${vendor}:${device} class ${class}]"
        done
        if [[ "${dev_count}" -gt 1 ]]; then
            note_warn "group ${gid} contains ${dev_count} devices (shared group: weaker isolation)"
        fi
        if [[ "${dev_count}" -eq 0 ]]; then
            note_warn "group ${gid} contains no devices (unexpected)"
        fi
    done
    if [[ "${group_count}" -eq 0 ]]; then
        note_fail "no IOMMU groups enumerated"
    else
        note_ok "${group_count} IOMMU groups enumerated"
    fi
else
    note_fail "${group_base} absent: IOMMU not active under this kernel"
fi
echo

# 5. Verdict: capability vs enforcement are reported separately.
echo "--- verdict ---"
echo "VT-d capability (silicon): present per inventory (not re-proven here)."
if [[ "${fail}" -ne 0 ]]; then
    echo "RESULT: FAIL - IOMMU enforcement could not be confirmed."
    echo "Do not run the untrusted-analysis VM profile until this passes."
    exit 1
elif [[ "${warn}" -ne 0 ]]; then
    echo "RESULT: WARN - IOMMU likely active but some evidence was unavailable."
    echo "Review warnings manually before relying on DMA isolation."
    exit 2
else
    echo "RESULT: OK - IOMMU active, interrupt remapping evidenced, groups enumerated."
    exit 0
fi
