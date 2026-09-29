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

# Specialty USB devices and compliance-test fixtures have no supported role
# on this ThinkPad. Their USB match/probe paths must not be compiled in.
for symbol in \
    CONFIG_USB_YUREX CONFIG_USB_LEGOTOWER CONFIG_USB_IDMOUSE \
    CONFIG_USB_MDC800 CONFIG_USB_CYTHERM CONFIG_USB_ADUTUX \
    CONFIG_USB_LD CONFIG_USB_TRANCEVIBRATOR CONFIG_USB_LCD \
    CONFIG_USB_IOWARRIOR CONFIG_USB_SISUSBVGA CONFIG_USB_MICROTEK \
    CONFIG_USB_APPLEDISPLAY CONFIG_USB_TEST \
    CONFIG_USB_EHSET_TEST_FIXTURE CONFIG_USB_LINK_LAYER_TEST; do
    expect "$symbol" removed
done

# Retain USB mass-storage class support, but not these model-specific bridge,
# card-reader, music-player, and button helpers.
for symbol in \
    CONFIG_USB_STORAGE_ALAUDA CONFIG_USB_STORAGE_DATAFAB \
    CONFIG_USB_STORAGE_ENE_UB6250 CONFIG_USB_STORAGE_FREECOM \
    CONFIG_USB_STORAGE_ISD200 CONFIG_USB_STORAGE_JUMPSHOT \
    CONFIG_USB_STORAGE_KARMA CONFIG_USB_STORAGE_ONETOUCH \
    CONFIG_USB_STORAGE_SDDR09 CONFIG_USB_STORAGE_SDDR55 \
    CONFIG_USB_STORAGE_USBAT CONFIG_USB_STORAGE_CYPRESS_ATACB; do
    expect "$symbol" removed
done

for symbol in \
    CONFIG_USB CONFIG_USB_XHCI_HCD CONFIG_USB_HID \
    CONFIG_USB_STORAGE CONFIG_USB_UAS CONFIG_MT7921U \
    CONFIG_SCSI CONFIG_BLK_DEV_SD CONFIG_BACKLIGHT_CLASS_DEVICE; do
    expect "$symbol" y
done

if [ "$failures" -ne 0 ]; then
    printf 'audit10 USB config gate: %d failures\n' "$failures"
    exit 1
fi
echo 'audit10 USB config gate: PASS'
