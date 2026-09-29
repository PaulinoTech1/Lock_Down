#!/usr/bin/env bash
# Fail closed on production security-policy drift in a resolved .config.
set -euo pipefail

config_file="${1:?usage: preflight-security.sh <resolved-.config>}"
[[ -r "$config_file" ]] || { echo "ERROR: config not readable: $config_file" >&2; exit 1; }

required_y=(
    SECURITY_LOCKDOWN_LSM SECURITY_LOCKDOWN_LSM_EARLY
    LOCK_DOWN_KERNEL_FORCE_INTEGRITY SECURITY_APPARMOR SECURITY_YAMA
    SECURITY_LANDLOCK INTEL_IOMMU IRQ_REMAP STACKPROTECTOR_STRONG
    FORTIFY_SOURCE HARDENED_USERCOPY STRICT_KERNEL_RWX EXPERT
)
required_n=(
    MODULES MAXSMP LOCK_DOWN_KERNEL_FORCE_NONE ACPI_DEBUGGER ACPI_DEBUG
    DEBUG_FS KGDB KGDB_KDB DYNAMIC_DEBUG FUNCTION_TRACER STACK_TRACER
)

fail=0
actual_value() {
    local symbol="$1" line
    line="$(grep -m1 "^CONFIG_${symbol}=" "$config_file" || true)"
    if [[ -n "$line" ]]; then
        printf '%s' "${line#*=}"
    elif grep -qx "# CONFIG_${symbol} is not set" "$config_file"; then
        printf 'n'
    else
        printf 'absent'
    fi
}

printf '%-5s %-42s %-10s %s\n' RESULT SYMBOL EXPECTED ACTUAL
for symbol in "${required_y[@]}"; do
    actual="$(actual_value "$symbol")"
    if [[ "$actual" == y ]]; then
        printf '%-5s %-42s %-10s %s\n' PASS "CONFIG_${symbol}" y "$actual"
    else
        printf '%-5s %-42s %-10s %s\n' FAIL "CONFIG_${symbol}" y "$actual" >&2
        fail=$((fail + 1))
    fi
done

for requirement in 'ARCH_MMAP_RND_BITS=32' 'ARCH_MMAP_RND_COMPAT_BITS=16'; do
    symbol="${requirement%%=*}"
    expected="${requirement#*=}"
    actual="$(actual_value "$symbol")"
    if [[ "$actual" == "$expected" ]]; then
        printf '%-5s %-42s %-10s %s\n' PASS "CONFIG_${symbol}" "$expected" "$actual"
    else
        printf '%-5s %-42s %-10s %s\n' FAIL "CONFIG_${symbol}" "$expected" "$actual" >&2
        fail=$((fail + 1))
    fi
done
for symbol in "${required_n[@]}"; do
    actual="$(actual_value "$symbol")"
    if [[ "$actual" == n || "$actual" == absent ]]; then
        printf '%-5s %-42s %-10s %s\n' PASS "CONFIG_${symbol}" n "$actual"
    else
        printf '%-5s %-42s %-10s %s\n' FAIL "CONFIG_${symbol}" n "$actual" >&2
        fail=$((fail + 1))
    fi
done

if (( fail > 0 )); then
    printf 'FATAL: %d production security-policy checks failed\n' "$fail" >&2
    exit 1
fi
printf 'OK: production security-policy gate passed (%d checks).\n' \
    "$((${#required_y[@]} + ${#required_n[@]} + 2))"
