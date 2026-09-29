#!/usr/bin/env bash
set -u

usage() {
    cat <<'EOF'
Usage: audit-config.sh [--project-root DIR] [--config FILE]

Read-only audit of the effective Linux kernel configuration.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${LOCK_DOWN_ROOT:-}"
CONFIG_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:?--project-root requires DIR}"; shift 2 ;;
        --config) CONFIG_FILE="${2:?--config requires FILE}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$PROJECT_ROOT" ]; then
    if [ -f "$PWD/config/hardened.config" ]; then
        PROJECT_ROOT="$PWD"
    else
        PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    fi
fi

if [ -z "$CONFIG_FILE" ]; then
    CONFIG_FILE="$(find "$PROJECT_ROOT" -maxdepth 2 -type f -path '*/.config' | sort | head -1)"
fi

[ -n "$CONFIG_FILE" ] || { echo "ERROR: no .config found; use --config" >&2; exit 1; }
[ -r "$CONFIG_FILE" ] || { echo "ERROR: config is not readable: $CONFIG_FILE" >&2; exit 1; }

value() {
    local symbol="$1" line
    line="$(grep -E "^${symbol}=|^# ${symbol} is not set$" "$CONFIG_FILE" | head -1 || true)"
    case "$line" in
        "${symbol}=y") echo y ;;
        "${symbol}=m") echo m ;;
        "# ${symbol} is not set") echo n ;;
        "") echo absent ;;
        *) echo "${line#*=}" ;;
    esac
}

check() {
    local symbol="$1" expected="$2" actual
    actual="$(value "$symbol")"
    if [ "$actual" = "$expected" ]; then
        printf 'PASS %-38s expected=%-6s actual=%s\n' "$symbol" "$expected" "$actual"
    else
        printf 'FAIL %-38s expected=%-6s actual=%s\n' "$symbol" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

show() {
    local symbol="$1"
    printf 'INFO %-38s actual=%s\n' "$symbol" "$(value "$symbol")"
}

failures=0
echo "=== Lock_Down effective configuration audit ==="
echo "project_root: $PROJECT_ROOT"
echo "config:       $CONFIG_FILE"
echo
echo "--- boot and hardware essentials ---"
check CONFIG_64BIT y
check CONFIG_X86_64 y
check CONFIG_SMP y
check CONFIG_PCI y
check CONFIG_ACPI y
check CONFIG_EFI y
check CONFIG_BLK_DEV_INITRD y
check CONFIG_DEVTMPFS y
check CONFIG_TMPFS y
check CONFIG_EXT4_FS y
check CONFIG_BLK_DEV_DM y
check CONFIG_DM_CRYPT y
check CONFIG_DRM_I915 y
check CONFIG_DRM_DISPLAY_DP_HELPER y
check CONFIG_DRM_DISPLAY_HDMI_HELPER y
check CONFIG_BLK_DEV_NVME y
check CONFIG_TCG_TPM y
check CONFIG_THINKPAD_ACPI y
check CONFIG_USB_XHCI_HCD y
check CONFIG_I2C_HID_ACPI y
check CONFIG_SERIO_I8042 y
check CONFIG_INET y
check CONFIG_IPV6 y
check CONFIG_NF_TABLES y
check CONFIG_NF_TABLES_INET y
check CONFIG_NF_CONNTRACK y
check CONFIG_NFT_CT y
check CONFIG_NFT_LOG y
check CONFIG_NFT_LIMIT y
echo
echo "--- Alder Lake power path ---"
check CONFIG_X86_INTEL_PSTATE y
check CONFIG_CPU_FREQ y
check CONFIG_INTEL_IDLE y
check CONFIG_NO_HZ_IDLE y
check CONFIG_HIGH_RES_TIMERS y
check CONFIG_MICROCODE y
check CONFIG_X86_THERMAL_VECTOR y
check CONFIG_INTEL_HFI_THERMAL y
check CONFIG_POWERCAP y
check CONFIG_INTEL_RAPL y
show CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE
show CONFIG_CPU_FREQ_GOV_SCHEDUTIL
show CONFIG_HZ_PERIODIC
echo
echo "--- security and isolation ---"
check CONFIG_SECURITY y
check CONFIG_SECURITY_APPARMOR y
check CONFIG_SECURITY_YAMA y
check CONFIG_SECURITY_LANDLOCK y
check CONFIG_SECURITY_LOCKDOWN_LSM y
check CONFIG_DEFAULT_SECURITY_APPARMOR y
check CONFIG_INTEL_IOMMU y
check CONFIG_IRQ_REMAP y
check CONFIG_MITIGATION_PAGE_TABLE_ISOLATION y
show CONFIG_KVM_INTEL
show CONFIG_MODULES
show CONFIG_MODULE_SIG_FORCE
show CONFIG_BPF_SYSCALL
show CONFIG_BPF_UNPRIV_DEFAULT_OFF
show CONFIG_USER_NS
show CONFIG_IO_URING
show CONFIG_EXPERT
show CONFIG_ARCH_MMAP_RND_BITS
show CONFIG_ARCH_MMAP_RND_COMPAT_BITS
show CONFIG_NR_CPUS
echo
echo "--- target-specific network/audio paths ---"
show CONFIG_MT7921U
show CONFIG_SND_HDA_INTEL
show CONFIG_SND_HDA_CODEC_REALTEK
check CONFIG_SND_HDA_CODEC_HDMI_INTEL y
check CONFIG_TYPEC y
check CONFIG_TYPEC_UCSI y
check CONFIG_UCSI_ACPI y
check CONFIG_TYPEC_DP_ALTMODE y
show CONFIG_SND_SOC_SOF_TOPLEVEL
show CONFIG_SND_SOC_SOF_PCI
show CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL
show CONFIG_SND_SOC_SOF_HDA_COMMON
show CONFIG_NF_TABLES
echo
echo "--- production debug exclusions ---"
for symbol in CONFIG_ACPI_DEBUG CONFIG_DEBUG_FS CONFIG_DYNAMIC_DEBUG CONFIG_KGDB CONFIG_STACK_TRACER CONFIG_KASAN CONFIG_KCSAN CONFIG_KPROBES CONFIG_FUNCTION_TRACER CONFIG_USB4 CONFIG_BT CONFIG_DRM_AMDGPU CONFIG_DRM_RADEON CONFIG_DRM_NOUVEAU CONFIG_IWLWIFI CONFIG_USB_VIDEO_CLASS; do
    actual="$(value "$symbol")"
    if [ "$actual" = y ] || [ "$actual" = m ]; then
        printf 'WARN %-38s actual=%s\n' "$symbol" "$actual"
    else
        printf 'PASS %-38s actual=%s\n' "$symbol" "$actual"
    fi
done

echo
echo "result: $failures required checks failed"
echo "Power conclusions still require live measurements; this script does not claim battery improvement."
[ "$failures" -eq 0 ]
