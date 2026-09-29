#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: diff-config.sh BASE_CONFIG CANDIDATE_CONFIG" >&2; }

[ "$#" -eq 2 ] || { usage; exit 2; }
BASE="$1"
CANDIDATE="$2"
[ -r "$BASE" ] || { echo "ERROR: unreadable baseline: $BASE" >&2; exit 1; }
[ -r "$CANDIDATE" ] || { echo "ERROR: unreadable candidate: $CANDIDATE" >&2; exit 1; }

base_norm="$(mktemp "${TMPDIR:-/tmp}/lock-down-config-base.XXXXXX")"
cand_norm="$(mktemp "${TMPDIR:-/tmp}/lock-down-config-cand.XXXXXX")"
trap 'rm -f "$base_norm" "$cand_norm"' EXIT

normalize() {
    awk '
        /^CONFIG_[A-Za-z0-9_]+=/{
            split($0, a, "="); print a[1] "=" substr($0, length(a[1]) + 2); next
        }
        /^# CONFIG_[A-Za-z0-9_]+ is not set$/ { print $2 "=n" }
    ' "$1" | sort -t '=' -k1,1
}

normalize "$BASE" >"$base_norm"
normalize "$CANDIDATE" >"$cand_norm"

echo "=== kernel configuration differences ==="
echo "baseline:  $BASE"
echo "candidate: $CANDIDATE"
echo
awk -F= '
    NR==FNR { base[$1]=$0; next }
    { cand[$1]=$0 }
    END {
        for (s in base) seen[s]=1
        for (s in cand) seen[s]=1
        for (s in seen) {
            b=(s in base ? base[s] : s "=<absent>")
            c=(s in cand ? cand[s] : s "=<absent>")
            if (b != c) print s "\t" b "\t" c
        }
    }
' "$base_norm" "$cand_norm" | sort -k1,1 | {
    printf '%-42s %-28s %s\n' SYMBOL BASELINE CANDIDATE
    printf '%-42s %-28s %s\n' '------' '--------' '---------'
    cat
}
