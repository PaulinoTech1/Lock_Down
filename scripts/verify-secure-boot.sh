#!/usr/bin/env bash
# Exit 0: required checks pass; 1: FAIL; 2: usage; 3: UNKNOWN. Read-only.
set -euo pipefail
[[ $# == 0 ]] || { echo 'usage: EXPECTED_KERNEL=release verify-secure-boot.sh' >&2; exit 2; }
base="${BOOT_EVIDENCE_ROOT:-}"
fail=0 unknown=0
result() {
    printf '[%s] %s: %s\n' "$1" "$2" "$3"
    case "$1" in FAIL) fail=1;; UNKNOWN) unknown=1;; esac
}
[[ -z "$base" ]] || printf 'INFO: offline evidence root: %s; not live verification\n' "$base"
if sb_state="$(mokutil --sb-state 2>/dev/null)"; then
    if grep -qx 'SecureBoot enabled' <<< "$sb_state" && ! grep -q 'SecureBoot disabled' <<< "$sb_state"; then
        result PASS secure-boot-state enabled
    elif grep -qx 'SecureBoot disabled' <<< "$sb_state"; then
        result FAIL secure-boot-state 'disabled; unacceptable for this profile'
    else
        result UNKNOWN secure-boot-state 'unrecognized evidence'
    fi
else
    result UNKNOWN secure-boot-state 'mokutil unavailable or query failed'
fi
if lockdown="$(cat "$base/sys/kernel/security/lockdown" 2>/dev/null)"; then
    case "$lockdown" in
        'none [integrity] confidentiality'|'none integrity [confidentiality]') result PASS kernel-lockdown "$lockdown";;
        '[none] integrity confidentiality') result FAIL kernel-lockdown none;;
        *) result UNKNOWN kernel-lockdown 'unrecognized evidence';;
    esac
else
    result UNKNOWN kernel-lockdown unreadable
fi
running="$(uname -r)"
if [[ -z "${EXPECTED_KERNEL:-}" ]]; then
    result UNKNOWN expected-kernel 'EXPECTED_KERNEL not set'
elif [[ "$running" == "$EXPECTED_KERNEL" ]]; then
    result PASS expected-kernel "$running"
else
    result FAIL expected-kernel "running $running, expected $EXPECTED_KERNEL"
fi
cfg=''
if [[ -r "$base/proc/config.gz" ]]; then
    cfg="$(gzip -cd -- "$base/proc/config.gz" 2>/dev/null || true)"
elif [[ -r "$base/boot/config-$running" ]]; then
    cfg="$(cat "$base/boot/config-$running")"
fi
if grep -qx '# CONFIG_MODULES is not set' <<< "$cfg" && ! grep -q '^CONFIG_MODULES=' <<< "$cfg"; then
    result NOT_APPLICABLE module-signatures 'monolithic kernel; no loadable modules'
elif grep -qx 'CONFIG_MODULES=y' <<< "$cfg"; then
    if grep -qx 'CONFIG_MODULE_SIG_FORCE=y' <<< "$cfg"; then
        result PASS module-policy 'forced signature policy configured; not a cryptographic module audit'
    else
        result FAIL module-policy 'loadable modules without CONFIG_MODULE_SIG_FORCE=y'
    fi
else
    result UNKNOWN module-policy 'kernel config unreadable or ambiguous'
fi
# Optional raw logs are informational, never promoted to PASS.
if [[ -z "$base" ]]; then
    dmesg 2>/dev/null | grep -iE 'secure.?boot|lockdown' | tail -5 | sed 's/^/INFO dmesg: /' || true
    efi-readvar 2>/dev/null | grep '^Variable ' | sed 's/^/INFO EFI inventory: /' || true
fi
(( fail == 0 )) || exit 1
(( unknown == 0 )) || exit 3
exit 0
