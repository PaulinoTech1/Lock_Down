#!/usr/bin/env bash
#
# check-firmware-updates.sh - Read-only firmware update availability check.
#
# Reports, per component: device name, current version, and whether an update
# is available, using fwupdmgr. Handles fwupdmgr missing (UNKNOWN) and the
# daemon being unreachable (graceful degradation).
#
# Read-only: this script never downloads, stages, or installs firmware.
#
set -euo pipefail

if ! command -v fwupdmgr >/dev/null 2>&1; then
    printf '[UNKNOWN] firmware-updates: fwupdmgr not installed; cannot enumerate firmware components.\n'
    exit 3
fi

# Machine-readable device listing where supported.
devices_json="$(fwupdmgr get-devices --json 2>/dev/null || true)"

if [ -z "$devices_json" ]; then
    printf '[UNKNOWN] firmware-updates: fwupdmgr get-devices produced no output; the fwupd daemon may be unreachable.\n'
    printf 'Hint: check that fwupd is running (systemctl status fwupd) and re-run.\n'
    exit 3
fi

# Prefer jq; fall back to python3 for JSON parsing. No other assumptions.
have_jq=0
have_py=0
command -v jq >/dev/null 2>&1 && have_jq=1
command -v python3 >/dev/null 2>&1 && have_py=1

if [ "$have_jq" -eq 0 ] && [ "$have_py" -eq 0 ]; then
    printf '[UNKNOWN] firmware-updates: device data retrieved but neither jq nor python3 is available to parse it.\n'
    printf 'Raw device count line (unparsed):\n'
    printf '%s\n' "$devices_json" | head -c 400
    printf '\n'
    exit 3
fi

printf 'Firmware components (from fwupdmgr get-devices):\n'
printf '%-45s %-18s %s\n' 'DEVICE' 'VERSION' 'UPDATE'

if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$devices_json" | jq -r '
        (.Devices // [])[] |
        "\(.Name // "unknown")\t\(.Version // "unknown")\t\(.VersionFormat // "")\t\(
            if (.Flags // []) | index("updatable") then "updatable-flag"
            elif (.UpdateState // 0) != 0 then "update-state=\(.UpdateState)"
            else "no-update-info" end
        )"' | while IFS=$'\t' read -r name version _vfmt state; do
        printf '%-45s %-18s %s\n' "${name:0:44}" "${version:0:17}" "$state"
    done
else
    printf '%s' "$devices_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for d in data.get("Devices", []):
    name = (d.get("Name") or "unknown")[:44]
    ver = (d.get("Version") or "unknown")[:17]
    flags = d.get("Flags") or []
    ustate = d.get("UpdateState") or 0
    if "updatable" in flags:
        state = "updatable-flag"
    elif ustate != 0:
        state = "update-state=%s" % ustate
    else:
        state = "no-update-info"
    print("%-45s %-18s %s" % (name, ver, state))
'
fi

printf '\nChecking for available updates (metadata refresh may take a moment)...\n'
updates_json="$(fwupdmgr get-updates --json 2>/dev/null || true)"

if [ -z "$updates_json" ]; then
    printf '[UNKNOWN] firmware-update-availability: fwupdmgr get-updates produced no output; daemon may be unreachable or metadata refresh failed.\n'
    printf '[WARN] update-install: this script never installs firmware; use fwupdmgr manually per docs/FIRMWARE.md.\n'
    exit 0
fi

if [ "$have_jq" -eq 1 ]; then
    count="$(printf '%s' "$updates_json" | jq '[.Devices // [] | .[] | select(.Releases // [] | length > 0)] | length')"
    if [ "$count" -gt 0 ]; then
        printf '[WARN] firmware-update-availability: %s component(s) have updates available.\n' "$count"
        printf '%s' "$updates_json" | jq -r '
            (.Devices // [])[] | select((.Releases // []) | length > 0) |
            "  - \(.Name // "unknown"): \(.Version // "?") -> \(.Releases[0].Version // "?") (\(.Releases[0].Urgency // "urgency-unknown"))"'
    else
        printf '[PASS] firmware-update-availability: no updates offered by fwupd for enumerated components.\n'
    fi
else
    printf '%s' "$updates_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
found = []
for d in data.get("Devices", []):
    rels = d.get("Releases") or []
    if rels:
        found.append((d.get("Name") or "unknown", d.get("Version") or "?",
                      rels[0].get("Version") or "?", rels[0].get("Urgency") or "urgency-unknown"))
if found:
    print("[WARN] firmware-update-availability: %d component(s) have updates available." % len(found))
    for name, cur, new, urg in found:
        print("  - %s: %s -> %s (%s)" % (name, cur, new, urg))
else:
    print("[PASS] firmware-update-availability: no updates offered by fwupd for enumerated components.")
'
fi

printf '[WARN] update-install: this script never installs firmware. Any update is a manual admin action per docs/FIRMWARE.md (AC power, version recording before/after, re-verify Secure Boot and TPM seal).\n'
