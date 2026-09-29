#!/usr/bin/env bash
# A production gate must reject policy drift in a resolved kernel config.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="${repo_root}/scripts/preflight-security.sh"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

printf '%s\n' \
    'CONFIG_SECURITY_LOCKDOWN_LSM=y' \
    'CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y' \
    'CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y' \
    'CONFIG_SECURITY_APPARMOR=y' \
    'CONFIG_SECURITY_YAMA=y' \
    'CONFIG_SECURITY_LANDLOCK=y' \
    'CONFIG_INTEL_IOMMU=y' \
    'CONFIG_IRQ_REMAP=y' \
    'CONFIG_STACKPROTECTOR_STRONG=y' \
    'CONFIG_FORTIFY_SOURCE=y' \
    'CONFIG_HARDENED_USERCOPY=y' \
    'CONFIG_STRICT_KERNEL_RWX=y' \
    'CONFIG_EXPERT=y' \
    'CONFIG_ARCH_MMAP_RND_BITS=32' \
    'CONFIG_ARCH_MMAP_RND_COMPAT_BITS=16' \
    '# CONFIG_MODULES is not set' \
    '# CONFIG_MAXSMP is not set' \
    'CONFIG_NR_CPUS=64' \
    '# CONFIG_ACPI_DEBUGGER is not set' \
    '# CONFIG_ACPI_DEBUG is not set' \
    '# CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE is not set' \
    '# CONFIG_DEBUG_FS is not set' \
    '# CONFIG_KGDB is not set' \
    '# CONFIG_KGDB_KDB is not set' \
    '# CONFIG_DYNAMIC_DEBUG is not set' \
    '# CONFIG_FUNCTION_TRACER is not set' \
    '# CONFIG_STACK_TRACER is not set' > "$fixture"

# Removing the gate or accepting a disabled hardening symbol must fail.
bash "$gate" "$fixture" >/dev/null
sed -i 's/^CONFIG_IRQ_REMAP=y$/# CONFIG_IRQ_REMAP is not set/' "$fixture"
if bash "$gate" "$fixture" >/dev/null 2>&1; then
    echo 'FAIL: disabled IRQ remapping passed the security gate' >&2
    exit 1
fi
sed -i 's/^# CONFIG_IRQ_REMAP is not set$/CONFIG_IRQ_REMAP=y/' "$fixture"

# Disabling EXPERT silently lowers the default ASLR entropy on x86_64.
sed -i 's/^CONFIG_ARCH_MMAP_RND_BITS=32$/CONFIG_ARCH_MMAP_RND_BITS=28/' "$fixture"
if bash "$gate" "$fixture" >/dev/null 2>&1; then
    echo 'FAIL: reduced mmap ASLR entropy passed the security gate' >&2
    exit 1
fi
sed -i 's/^CONFIG_ARCH_MMAP_RND_BITS=28$/CONFIG_ARCH_MMAP_RND_BITS=32/' "$fixture"

sed -i 's/^# CONFIG_KGDB is not set$/CONFIG_KGDB=y/' "$fixture"
if bash "$gate" "$fixture" >/dev/null 2>&1; then
    echo 'FAIL: enabled kernel debugger passed the security gate' >&2
    exit 1
fi
sed -i 's/^CONFIG_KGDB=y$/# CONFIG_KGDB is not set/' "$fixture"

# Inherited production-debug capability must fail, even if other policy holds.
sed -i 's/^# CONFIG_ACPI_DEBUGGER is not set$/CONFIG_ACPI_DEBUGGER=y/' "$fixture"
if bash "$gate" "$fixture" >/dev/null 2>&1; then
    echo 'FAIL: enabled ACPI debugger passed the security gate' >&2
    exit 1
fi
echo 'PASS: security gate accepts the profile and rejects policy drift'
