#!/usr/bin/env bash
#
# verify-module-signatures.sh - Read-only audit of loaded module signatures.
#
# For each loaded module, reports whether it is signed and, where the kernel
# exposes signer identity, by which key. Unsigned loaded modules are flagged.
#
# Read-only: this script changes no system state.
#
# Method: kernels built with module signature support expose
# /sys/module/<name>/signature for some modules; modinfo shows the signature
# section of the module file when readable. Where neither is available the
# module is reported as UNKNOWN, never assumed signed or unsigned.
#
set -euo pipefail

SYSFS_SIG=0
MODINFO_SIG=0

if ls -d /sys/module/*/signature >/dev/null 2>&1; then
    SYSFS_SIG=1
fi
if command -v modinfo >/dev/null 2>&1; then
    MODINFO_SIG=1
fi

if [ "$SYSFS_SIG" -eq 0 ] && [ "$MODINFO_SIG" -eq 0 ]; then
    printf 'UNKNOWN: neither /sys/module/*/signature nor modinfo is available; cannot audit module signatures on this kernel.\n'
    exit 3
fi

total=0
signed=0
unsigned=0
unknown=0

while IFS= read -r modpath; do
    mod="${modpath#/sys/module/}"
    mod="${mod%/signature}"
    total=$((total + 1))

    signer="unknown-signer"
    state="UNKNOWN"

    if [ "$SYSFS_SIG" -eq 1 ] && [ -r "/sys/module/$mod/signature" ]; then
        sig="$(cat "/sys/module/$mod/signature" 2>/dev/null || true)"
        if [ -n "$sig" ]; then
            state="SIGNED"
            # sysfs signature content varies; keep the first line as the identity hint.
            signer="$(printf '%s' "$sig" | head -n 1 | cut -c1-80)"
        else
            state="UNSIGNED"
        fi
    elif [ "$MODINFO_SIG" -eq 1 ]; then
        info="$(modinfo -F signature "$mod" 2>/dev/null || true)"
        if [ -n "$info" ]; then
            state="SIGNED"
            signer="$(printf '%s' "$info" | head -n 1 | cut -c1-80)"
        else
            # modinfo prints nothing for signature when the module file has no
            # signature section OR when modinfo cannot read the module file.
            # Distinguish: if the module file exists and is readable but has
            # no appended signature marker, it is unsigned.
            kofile="$(modinfo -n "$mod" 2>/dev/null || true)"
            if [ -n "$kofile" ] && [ -r "$kofile" ]; then
                if grep -q -a '~Module signature appended~' "$kofile" 2>/dev/null; then
                    state="SIGNED"
                    signer="signature-present-signer-not-exposed"
                else
                    state="UNSIGNED"
                fi
            else
                state="UNKNOWN"
            fi
        fi
    fi

    case "$state" in
        SIGNED)   signed=$((signed + 1));   printf 'SIGNED   %-28s key: %s\n' "$mod" "$signer" ;;
        UNSIGNED) unsigned=$((unsigned + 1)); printf 'UNSIGNED %-28s <-- flagged: loaded without a signature\n' "$mod" ;;
        *)        unknown=$((unknown + 1));  printf 'UNKNOWN  %-28s (signature state not readable)\n' "$mod" ;;
    esac
done < <(lsmod | awk 'NR>1 {print $1}' | sort -u)

printf '\nSummary: %d loaded modules: %d signed, %d unsigned, %d unknown.\n' \
    "$total" "$signed" "$unsigned" "$unknown"

if [ "$unsigned" -gt 0 ]; then
    printf 'FAIL: %d unsigned module(s) are loaded. Under Secure Boot with MODULE_SIG_FORCE this must not happen.\n' "$unsigned"
    exit 1
fi
if [ "$unknown" -gt 0 ]; then
    printf 'WARN: %d module(s) could not be verified; treat as unverified, not as signed.\n' "$unknown"
    exit 2
fi
printf 'PASS: all loaded modules carry signatures.\n'
exit 0
