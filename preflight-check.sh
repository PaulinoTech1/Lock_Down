#!/usr/bin/env bash
#
# preflight-check.sh -- fail-fast gate for Lock_Down kernel configs.
#
# Why this exists: three times (framebuffer console, dm-crypt, and the
# userspace basics that disqualified build #6), hand-appended CONFIG_=y lines
# were silently undone by `make olddefconfig`, which resolves dependencies by
# switching things OFF. Each discovery cost a full compile and a failed boot.
#
# Run this AFTER `make olddefconfig` and BEFORE compiling. It exits 1 if any
# symbol in the [required] tier of required-symbols.txt is not =y.
#
# Usage:
#   scripts/preflight-check.sh <path-to-.config> [path-to-required-symbols.txt]
#
# This build is monolithic by design, so =m counts as a failure for
# [required] symbols. A required symbol entirely absent from the .config is
# also a failure: 6.18.53's Kconfig silently drops assigned symbols whose
# dependencies are unmet (sym_calc_value clears SYMBOL_WRITE for invisible
# symbols; conf_write skips them), so "absent" means a dependency is broken
# or the symbol was renamed upstream. Either needs a human decision.

set -u

CONFIG_FILE="${1:?usage: preflight-check.sh <config-file> [symbols-file]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMBOLS_FILE="${2:-${SCRIPT_DIR}/../config/required-symbols.txt}"

[ -f "$CONFIG_FILE" ] || { echo "ERROR: config file not found: $CONFIG_FILE" >&2; exit 1; }
[ -r "$CONFIG_FILE" ] || { echo "ERROR: config file not readable: $CONFIG_FILE (permission denied -- try sudo)" >&2; exit 1; }
[ -f "$SYMBOLS_FILE" ] || { echo "ERROR: symbols file not found: $SYMBOLS_FILE" >&2; exit 1; }

tier="required"
pass=0; fail=0; warn_n=0
failed_symbols=""

check_symbol() { # $1 = CONFIG_NAME
    local sym="$1" state val
    if grep -q "^${sym}=y$" "$CONFIG_FILE"; then
        pass=$((pass + 1))
        return 0
    fi
    if grep -q "^# ${sym} is not set$" "$CONFIG_FILE"; then
        state="explicitly disabled"
    elif grep -q "^${sym}=" "$CONFIG_FILE"; then
        val="$(grep "^${sym}=" "$CONFIG_FILE" | head -1 | cut -d= -f2)"
        state="set to '${val}' (need =y: this build is monolithic)"
    else
        # Absent entirely. In 6.18.53 Kconfig silently drops assigned symbols
        # whose dependencies are unmet, so absence usually means a broken
        # dependency, not a typo. Fail closed; a genuine upstream rename is
        # fixed by updating required-symbols.txt, consciously.
        if [ "$tier" = "required" ]; then
            echo "FAIL  [required] $sym: absent from .config (dependency unmet and Kconfig dropped it, or renamed upstream)"
            fail=$((fail + 1))
            failed_symbols="${failed_symbols} ${sym}"
        else
            echo "WARN  [warn] $sym absent from .config (renamed or removed upstream?)"
            warn_n=$((warn_n + 1))
        fi
        return 0
    fi
    if [ "$tier" = "required" ]; then
        echo "FAIL  [required] $sym: $state"
        fail=$((fail + 1))
        failed_symbols="${failed_symbols} ${sym}"
    else
        echo "WARN  [warn] $sym: $state"
        warn_n=$((warn_n + 1))
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$line" in
        ''|\#*) continue ;;
        '[required]') tier="required"; continue ;;
        '[warn]') tier="warn"; continue ;;
    esac
    sym="$(printf '%s' "$line" | cut -d= -f1)"
    case "$sym" in
        CONFIG_*) check_symbol "$sym" ;;
        *) echo "WARN  ignoring malformed line: $line" >&2; warn_n=$((warn_n + 1)) ;;
    esac
done < "$SYMBOLS_FILE"

echo "----"
echo "preflight: pass=${pass} fail=${fail} warn=${warn_n}"
if [ "$fail" -gt 0 ]; then
    echo "FATAL:${failed_symbols}"
    echo "Do not compile. Fix the config (see config/build7-fixups.txt),"
    echo "re-run olddefconfig, then re-run this script."
    exit 1
fi
echo "OK: all required symbols are =y."
exit 0
