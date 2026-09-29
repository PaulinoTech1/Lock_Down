#!/usr/bin/env bash
set -u

usage() { echo "Usage: validate-boot-critical.sh CONFIG [SYMBOLS_FILE]" >&2; }

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage; exit 2; }
CONFIG_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYMBOLS_FILE="${2:-$PROJECT_ROOT/config/required-symbols.txt}"

[ -r "$CONFIG_FILE" ] || { echo "ERROR: unreadable config: $CONFIG_FILE" >&2; exit 1; }
[ -r "$SYMBOLS_FILE" ] || { echo "ERROR: unreadable symbols file: $SYMBOLS_FILE" >&2; exit 1; }

actual_value() {
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

tier=required
pass=0
fail=0
warn=0
echo "=== boot-critical configuration validation ==="
echo "config:  $CONFIG_FILE"
echo "symbols: $SYMBOLS_FILE"

while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$line" in
        ''|'#'*) continue ;;
        '[required]') tier=required; continue ;;
        '[warn]') tier=warn; continue ;;
    esac
    symbol="${line%%=*}"
    case "$symbol" in CONFIG_*) ;; *) continue ;; esac
    expected="${line#*=}"
    actual="$(actual_value "$symbol")"
    if [ "$actual" = "$expected" ]; then
        printf 'PASS %-36s expected=%-3s actual=%s\n' "$symbol" "$expected" "$actual"
        pass=$((pass + 1))
    elif [ "$tier" = required ]; then
        printf 'FAIL %-36s expected=%-3s actual=%s\n' "$symbol" "$expected" "$actual"
        fail=$((fail + 1))
    else
        printf 'WARN %-36s expected=%-3s actual=%s\n' "$symbol" "$expected" "$actual"
        warn=$((warn + 1))
    fi
done < "$SYMBOLS_FILE"

echo "----"
echo "pass=$pass fail=$fail warn=$warn"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: do not compile or install this configuration until required symbols resolve correctly."
    exit 1
fi
echo "PASS: all required boot-critical symbols resolve as requested."
