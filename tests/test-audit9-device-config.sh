#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
    echo "usage: $0 RESOLVED_CONFIG" >&2
    exit 2
fi

config_file="$1"
failures=0

state() {
    local symbol="$1" line
    line="$(grep -E "^${symbol}=|^# ${symbol} is not set$" "$config_file" | head -1 || true)"
    case "$line" in
        "${symbol}=y") echo y ;;
        "${symbol}=m") echo m ;;
        "# ${symbol} is not set") echo n ;;
        '') echo absent ;;
        *) echo "${line#*=}" ;;
    esac
}

expect() {
    local symbol="$1" expected="$2" actual
    actual="$(state "$symbol")"
    if [ "$expected" = removed ]; then
        case "$actual" in n|absent) return ;; esac
    elif [ "$actual" = "$expected" ]; then
        return
    fi
    printf 'FAIL %s expected=%s actual=%s\n' "$symbol" "$expected" "$actual"
    failures=$((failures + 1))
}

# These are the parent switches for audit9's unused device/protocol families.
for symbol in \
    CONFIG_USB_GADGET CONFIG_USB_SERIAL CONFIG_USB_ACM CONFIG_USB_PRINTER \
    CONFIG_USB_PULSE8_CEC CONFIG_USB_RAINSHADOW_CEC \
    CONFIG_USB_DWC3 CONFIG_USB_MUSB_HDRC CONFIG_USB_ISP1760 \
    CONFIG_USB_ISP1760_HCD \
    CONFIG_USB_NET_DRIVERS CONFIG_INPUT_TOUCHSCREEN \
    CONFIG_TIPC CONFIG_RDS CONFIG_L2TP CONFIG_IP_SCTP CONFIG_MPTCP \
    CONFIG_NET_ACT_CT CONFIG_NF_CONNTRACK_OVS \
    CONFIG_NF_CT_PROTO_SCTP CONFIG_NF_NAT_OVS \
    CONFIG_NETFILTER_XT_MATCH_L2TP CONFIG_NETFILTER_XT_MATCH_SCTP \
    CONFIG_IP_VS_PROTO_SCTP CONFIG_NET_ACT_MPLS \
    CONFIG_NFC CONFIG_VSOCKETS CONFIG_OPENVSWITCH CONFIG_MPLS CONFIG_N_GSM \
    CONFIG_NET_DSA CONFIG_ARCNET CONFIG_FDDI CONFIG_WAN \
    CONFIG_COMEDI CONFIG_IIO CONFIG_DRM_XE CONFIG_DRM_VMWGFX \
    CONFIG_DRM_QXL CONFIG_DRM_VIRTIO_GPU CONFIG_DRM_BOCHS \
    CONFIG_DRM_CIRRUS_QEMU CONFIG_IKHEADERS \
    CONFIG_SECURITY_SELINUX CONFIG_SECURITY_SMACK \
    CONFIG_SECURITY_TOMOYO CONFIG_SECURITY_IPE \
    CONFIG_SECURITY_SAFESETID; do
    expect "$symbol" removed
done

# The physical SYNA8018 touchpad binds hid-multitouch over I2C; it is not a
# touchscreen. USB host/storage and the MT7921U USB Wi-Fi path must also stay.
for symbol in \
    CONFIG_HID_MULTITOUCH CONFIG_I2C_HID_ACPI CONFIG_USB \
    CONFIG_USB_XHCI_HCD CONFIG_USB_HID CONFIG_USB_STORAGE CONFIG_USB_UAS \
    CONFIG_MT7921U CONFIG_DRM_I915 CONFIG_DRM_DISPLAY_DP_HELPER \
    CONFIG_DRM_DISPLAY_HDMI_HELPER CONFIG_TYPEC_DP_ALTMODE \
    CONFIG_SND_HDA_INTEL CONFIG_SND_SOC_SOF_TOPLEVEL \
    CONFIG_KVM_INTEL CONFIG_INTEL_IOMMU CONFIG_VHOST_NET \
    CONFIG_EXT4_FS CONFIG_SQUASHFS CONFIG_AUTOFS_FS CONFIG_FUSE_FS \
    CONFIG_DM_CRYPT CONFIG_KEXEC CONFIG_KEXEC_FILE CONFIG_CRASH_DUMP \
    CONFIG_X86_MSR CONFIG_SECURITY_APPARMOR CONFIG_SECURITY_YAMA \
    CONFIG_SECURITY_LANDLOCK CONFIG_SECURITY_LOCKDOWN_LSM \
    CONFIG_IMA CONFIG_EVM; do
    expect "$symbol" y
done

expect CONFIG_LSM '"landlock,lockdown,yama,integrity,apparmor"'
expect CONFIG_MEDIA_SUPPORT removed
expect CONFIG_RC_CORE removed

if [ "$failures" -ne 0 ]; then
    printf 'audit9 device config gate: %d failures\n' "$failures"
    exit 1
fi
echo 'audit9 device config gate: PASS'
