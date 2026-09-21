#!/usr/bin/env bash
#
# verify-secure-boot.sh - Read-only Secure Boot state checker.
#
# Reports per-check results as PASS / WARN / FAIL / UNKNOWN. A check that
# cannot be verified is reported as UNKNOWN, never PASS.
#
# Read-only: this script changes no system state.
#
set -euo pipefail

EXPECTED_KERNEL="${EXPECTED_KERNEL:-}"   # optional: expected running kernel version string

result() {
    # result <STATUS> <check-name> <detail>
    printf '[%s] %s: %s\n' "$1" "$2" "$3"
}

# ---------------------------------------------------------------- secure boot state
if command -v mokutil >/dev/null 2>&1; then
    sb_state="$(mokutil --sb-state 2>&1 || true)"
    case "$sb_state" in
        *SecureBoot*enabled*)
            result PASS "secure-boot-state" "mokutil reports SecureBoot enabled" ;;
        *SecureBoot*disabled*)
            result WARN "secure-boot-state" "mokutil reports SecureBoot disabled (expected during Phase A/B bringup)" ;;
        *)
            result UNKNOWN "secure-boot-state" "mokutil output not parseable: $sb_state" ;;
    esac
else
    result UNKNOWN "secure-boot-state" "mokutil not installed"
fi

# ---------------------------------------------------------------- EFI variables: PK, KEK, db, dbx
if command -v efi-readvar >/dev/null 2>&1; then
    readvar_out="$(efi-readvar 2>&1 || true)"
    for var in PK KEK db dbx; do
        if printf '%s' "$readvar_out" | grep -q "^Variable $var,"; then
            result PASS "efi-var-$var" "variable present"
        else
            if [ "$var" = "PK" ]; then
                result WARN "efi-var-$var" "PK not present: platform is in Setup Mode"
            else
                result WARN "efi-var-$var" "variable not present"
            fi
        fi
    done
else
    result UNKNOWN "efi-var-PK"  "efi-readvar not installed; cannot confirm PK presence"
    result UNKNOWN "efi-var-KEK" "efi-readvar not installed; cannot confirm KEK presence"
    result UNKNOWN "efi-var-db"  "efi-readvar not installed; cannot confirm db presence"
    result UNKNOWN "efi-var-dbx" "efi-readvar not installed; cannot confirm dbx presence"
fi

# ---------------------------------------------------------------- kernel lockdown
if [ -r /sys/kernel/security/lockdown ]; then
    lockdown="$(cat /sys/kernel/security/lockdown)"
    # Format: "[none] integrity confidentiality" with the active mode bracketed.
    active="$(printf '%s' "$lockdown" | grep -o '\[[^]]*\]' | tr -d '[]' || true)"
    case "$active" in
        integrity|confidentiality)
            result PASS "kernel-lockdown" "lockdown active: $active" ;;
        none)
            result WARN "kernel-lockdown" "lockdown mode is 'none' (Secure Boot off or not enforced)" ;;
        *)
            result UNKNOWN "kernel-lockdown" "could not parse lockdown state: $lockdown" ;;
    esac
else
    result UNKNOWN "kernel-lockdown" "/sys/kernel/security/lockdown not readable"
fi

if dmesg_out="$(dmesg 2>/dev/null | grep -i -E 'secure.?boot|lockdown' | tail -5)"; then
    if [ -n "$dmesg_out" ]; then
        while IFS= read -r line; do
            result PASS "dmesg-boot-integrity" "$line"
        done <<< "$dmesg_out"
    else
        result UNKNOWN "dmesg-boot-integrity" "no secure-boot/lockdown lines in dmesg"
    fi
else
    result UNKNOWN "dmesg-boot-integrity" "dmesg not readable"
fi

# ---------------------------------------------------------------- module signature enforcement
# MODULE_SIG_FORCE is a build-time config; at runtime the observable state is
# whether unsigned modules are rejected. The definitive test is the manual
# unsigned-module rejection procedure in docs/SECURE_BOOT.md. Here we report
# the readable config and sysfs state honestly.
if [ -r /proc/config.gz ]; then
    cfg="$(zcat /proc/config.gz 2>/dev/null || true)"
elif [ -r "/boot/config-$(uname -r)" ]; then
    cfg="$(cat "/boot/config-$(uname -r)" 2>/dev/null || true)"
else
    cfg=""
fi

if [ -n "$cfg" ]; then
    if printf '%s' "$cfg" | grep -q '^CONFIG_MODULE_SIG_FORCE=y'; then
        result PASS "module-sig-force-config" "CONFIG_MODULE_SIG_FORCE=y in running kernel config"
    elif printf '%s' "$cfg" | grep -q '^CONFIG_MODULE_SIG=y'; then
        result WARN "module-sig-force-config" "CONFIG_MODULE_SIG=y but MODULE_SIG_FORCE not set: signatures checked only if enforced"
    else
        result WARN "module-sig-force-config" "module signature support not found in running kernel config"
    fi
else
    result UNKNOWN "module-sig-force-config" "kernel config not readable; cannot confirm MODULE_SIG_FORCE"
fi

# /proc/sys/kernel/modules_disabled: 1 means module loading is fully disabled
# (stronger than signature enforcement); 0 is normal. Informational only.
if [ -r /proc/sys/kernel/modules_disabled ]; then
    md="$(cat /proc/sys/kernel/modules_disabled)"
    if [ "$md" = "1" ]; then
        result PASS "modules-disabled" "module loading fully disabled at runtime"
    else
        result PASS "modules-disabled" "module loading allowed (0); signature policy governs"
    fi
else
    result UNKNOWN "modules-disabled" "/proc/sys/kernel/modules_disabled not readable"
fi

# ---------------------------------------------------------------- running kernel identity
running="$(uname -r)"
result PASS "running-kernel" "running kernel: $running"
if [ -n "$EXPECTED_KERNEL" ]; then
    if [ "$running" = "$EXPECTED_KERNEL" ]; then
        result PASS "expected-kernel" "running kernel matches expected: $EXPECTED_KERNEL"
    else
        result FAIL "expected-kernel" "running $running, expected $EXPECTED_KERNEL (distro rescue may be booted)"
    fi
else
    result UNKNOWN "expected-kernel" "EXPECTED_KERNEL not set; cannot tell signed custom kernel from distro rescue by version alone (use module key IDs)"
fi

printf '\nDone. Statuses: PASS = verified, WARN = degraded/expected-during-bringup, FAIL = mismatch, UNKNOWN = could not verify.\n'
