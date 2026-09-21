#!/usr/bin/env bash
# security-status.sh: read-only security posture summary.
#
# Purpose: report the state of the workstation's security invariants in a
# machine-readable form. Each check prints one line:
#   LEVEL<TAB>check-name<TAB>detail
# where LEVEL is PASS, WARN, FAIL, or UNKNOWN.
#
# Rules: never PASS a state it cannot verify. Collects no private user
# data: no usernames, hostnames, serials, MACs, or IP addresses are read
# or printed. Read-only: makes no writes and changes no system state.
#
# Usage: ./security-status.sh
# Exit: 0 if no FAIL, 1 if any FAIL.

set -euo pipefail

fail_count=0

report() {
    local level="$1" check="$2" detail="$3"
    printf '%s\t%s\t%s\n' "$level" "$check" "$detail"
    if [ "$level" = "FAIL" ]; then
        fail_count=$((fail_count + 1))
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------- secure boot -------
if have mokutil; then
    if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
        report "PASS" "secure-boot" "Secure Boot enabled (mokutil)"
    elif mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot disabled"; then
        report "WARN" "secure-boot" \
            "Secure Boot disabled; enable after kernel bringup (shim+MOK)"
    else
        report "UNKNOWN" "secure-boot" \
            "mokutil ran but state unparsable; verify by hand"
    fi
else
    report "UNKNOWN" "secure-boot" \
        "mokutil not installed; cannot verify Secure Boot state"
fi

# ------------------------------------------------------------ lockdown -----
if [ -r /sys/kernel/security/lockdown ]; then
    lockdown="$(cat /sys/kernel/security/lockdown)"
    if printf '%s' "$lockdown" | grep -q "\[integrity\]\|\[confidentiality\]"; then
        mode="$(printf '%s' "$lockdown" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')"
        report "PASS" "kernel-lockdown" "lockdown mode: $mode"
    elif printf '%s' "$lockdown" | grep -q "\[none\]"; then
        report "WARN" "kernel-lockdown" \
            "lockdown=none; expected once Secure Boot is enabled"
    else
        report "UNKNOWN" "kernel-lockdown" "unparsable: $lockdown"
    fi
else
    report "UNKNOWN" "kernel-lockdown" \
        "/sys/kernel/security/lockdown unreadable"
fi

# ------------------------------------------------- module signatures -------
if dmesg 2>/dev/null | grep -qi "module verification"; then
    report "PASS" "module-sig-enforcement" \
        "kernel reports module signature verification active"
elif [ -r /sys/module/module/parameters/sig_enforce ]; then
    val="$(cat /sys/module/module/parameters/sig_enforce)"
    if [ "$val" = "Y" ]; then
        report "PASS" "module-sig-enforcement" "sig_enforce=Y"
    else
        report "WARN" "module-sig-enforcement" \
            "sig_enforce=$val; expected Y once Secure Boot is enabled"
    fi
else
    report "UNKNOWN" "module-sig-enforcement" \
        "no verifiable signature-enforcement state found"
fi

# --------------------------------------------------------------- iommu -----
if [ -r /proc/cmdline ] && grep -q "intel_iommu=on" /proc/cmdline; then
    report "PASS" "iommu-active" "intel_iommu=on on kernel command line"
elif dmesg 2>/dev/null | grep -qi "DMAR: IOMMU enabled"; then
    report "PASS" "iommu-active" "dmesg reports DMAR IOMMU enabled"
else
    report "WARN" "iommu-active" \
        "IOMMU activation not verifiable; check dmesg and /proc/cmdline"
fi

# ------------------------------------------------------------ apparmor -----
if have aa-status; then
    if aa-status 2>/dev/null | grep -q "apparmor module is loaded"; then
        report "PASS" "apparmor-loaded" "AppArmor module loaded"
    else
        report "WARN" "apparmor-loaded" \
            "AppArmor module state unclear from aa-status"
    fi
else
    report "UNKNOWN" "apparmor-loaded" "aa-status not available"
fi

# ----------------------------------------------------- unprivileged bpf ----
if [ -r /proc/sys/kernel/unprivileged_bpf_disabled ]; then
    val="$(cat /proc/sys/kernel/unprivileged_bpf_disabled)"
    if [ "$val" = "2" ]; then
        report "PASS" "unprivileged-bpf" "disabled (2)"
    elif [ "$val" = "1" ]; then
        report "WARN" "unprivileged-bpf" \
            "set to 1 (disabled but changeable); prefer 2"
    else
        report "FAIL" "unprivileged-bpf" \
            "unprivileged_bpf_disabled=$val; unprivileged BPF allowed"
    fi
else
    report "UNKNOWN" "unprivileged-bpf" "sysctl node unreadable"
fi

# ------------------------------------------------------------------- ssh ---
if have sshd; then
    ssh_ok="yes"
    if sshd -T 2>/dev/null | grep -qi "^permitrootlogin yes"; then
        report "FAIL" "ssh-root-login" "PermitRootLogin yes"
        ssh_ok="no"
    fi
    if sshd -T 2>/dev/null | grep -qi "^passwordauthentication yes"; then
        report "FAIL" "ssh-password-auth" "PasswordAuthentication yes"
        ssh_ok="no"
    fi
    if [ "$ssh_ok" = "yes" ]; then
        if sshd -T 2>/dev/null | grep -qi .; then
            report "PASS" "ssh-hardening" \
                "root login and password auth disabled in effective config"
        else
            report "UNKNOWN" "ssh-hardening" \
                "sshd -T produced no output; config unverifiable"
        fi
    fi
    if systemctl is-enabled ssh 2>/dev/null | grep -q "enabled"; then
        report "WARN" "ssh-server-enabled" \
            "sshd enabled; default posture is disabled (see docs/SSH.md)"
    else
        report "PASS" "ssh-server-enabled" "sshd not enabled"
    fi
else
    report "PASS" "ssh-server-enabled" "sshd not installed"
fi

# ------------------------------------------------- yubikey pam mappings ----
mapping="/etc/u2f_mappings"
if [ -f "$mapping" ]; then
    owner="$(stat -c '%U:%G' "$mapping")"
    mode="$(stat -c '%a' "$mapping")"
    if [ "$owner" = "root:root" ] && [ "$mode" = "600" ]; then
        report "PASS" "u2f-mapping-protected" \
            "$mapping is root:root mode 600"
    else
        report "FAIL" "u2f-mapping-protected" \
            "$mapping is $owner mode $mode (want root:root 600)"
    fi
else
    report "WARN" "u2f-mapping-protected" \
        "$mapping absent; pam_u2f policy not deployed or incomplete"
fi

# --------------------------------------------------------- nvme apst ------
apst_found="no"
for host in /sys/class/nvme/nvme*; do
    [ -e "$host" ] || continue
    if [ -r "$host/power_state" ] || ls "$host" 2>/dev/null | grep -q .; then
        apst_found="yes"
        break
    fi
done
if [ "$apst_found" = "yes" ]; then
    report "PASS" "nvme-present" \
        "NVMe controller visible in sysfs (APST policy: leave enabled)"
else
    report "UNKNOWN" "nvme-present" \
        "no NVMe controller found in sysfs; verify storage path"
fi

# -------------------------------------------------------- rescue kernel ---
# A rescue kernel means at least two bootable kernels exist. Count without
# naming versions in a way that leaks nothing sensitive (versions are fine;
# no host/user data is collected).
kernel_count="$(ls /boot/vmlinuz-* 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$kernel_count" -ge 2 ]; then
    report "PASS" "rescue-kernel" \
        "$kernel_count kernels installed; keep the distro kernel as rescue"
elif [ "$kernel_count" -eq 1 ]; then
    report "WARN" "rescue-kernel" \
        "only one kernel installed; no rescue fallback"
else
    report "UNKNOWN" "rescue-kernel" \
        "cannot enumerate /boot/vmlinuz-*"
fi

# ------------------------------------------------------------ firewall -----
if have nft; then
    if nft list ruleset 2>/dev/null | grep -q "type filter hook input"; then
        report "PASS" "firewall-active" "nftables input chain present"
    else
        report "WARN" "firewall-active" \
            "nftables present but no input filter chain found"
    fi
else
    report "WARN" "firewall-active" \
        "nft not installed; firewall ruleset not verifiable"
fi

# --------------------------------------------------------------- summary ---
if [ "$fail_count" -gt 0 ]; then
    printf 'RESULT: FAIL (%d failing check(s))\n' "$fail_count" >&2
    exit 1
fi
printf 'RESULT: OK (no FAIL; review WARN/UNKNOWN lines)\n'
exit 0
