#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
    echo "usage: $0 RESOLVED_CONFIG" >&2
    exit 2
fi

config_file="$1"
failures=0

expect() {
    local symbol="$1" expected="$2" line
    line="$(grep -E "^${symbol}=|^# ${symbol} is not set$" "$config_file" | head -1 || true)"
    case "$line" in
        "${symbol}=y") actual=y ;;
        "${symbol}=m") actual=m ;;
        "# ${symbol} is not set") actual=n ;;
        '') actual=absent ;;
        *) actual="${line#*=}" ;;
    esac
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s expected=%s actual=%s\n' "$symbol" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

# This candidate deliberately removes capture, TV, radio, SDR, and IR support.
expect CONFIG_MEDIA_SUPPORT n
expect CONFIG_RC_CORE n
expect CONFIG_MEDIA_TEST_SUPPORT absent
expect CONFIG_VIDEO_VIVID absent
expect CONFIG_DVB_CORE absent

# HDMI CEC is distinct from IR/capture; keep it for external-display safety.
expect CONFIG_CEC_CORE y
expect CONFIG_CEC_NOTIFIER y

# A media-tree reduction must not silently remove exercised laptop paths.
for symbol in \
    CONFIG_DRM_I915 CONFIG_DRM_DISPLAY_DP_HELPER \
    CONFIG_DRM_DISPLAY_HDMI_HELPER CONFIG_HID_MULTITOUCH \
    CONFIG_I2C_HID_ACPI CONFIG_SERIO_I8042 \
    CONFIG_SND_HDA_INTEL CONFIG_SND_SOC_SOF_TOPLEVEL \
    CONFIG_MT7921U CONFIG_USB_STORAGE CONFIG_USB_UAS \
    CONFIG_TYPEC_DP_ALTMODE CONFIG_BLK_DEV_NVME \
    CONFIG_EXT4_FS CONFIG_SQUASHFS CONFIG_VFAT_FS \
    CONFIG_DM_CRYPT CONFIG_KVM_INTEL CONFIG_INTEL_IOMMU; do
    expect "$symbol" y
done

if [ "$failures" -ne 0 ]; then
    printf 'audit8 media config gate: %d failures\n' "$failures"
    exit 1
fi
echo 'audit8 media config gate: PASS'
