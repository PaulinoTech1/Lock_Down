#!/usr/bin/env bash
# Offline collection/preflight only. Never pass --do-suspend.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir -p "$t/evidence/sys/power" "$t/output"
chmod 700 "$t/output"
export SUSPEND_EVIDENCE_ROOT="$t/evidence" SUSPEND_DIAG_DIR="$t/output"
printf '[s2idle] deep\n' > "$t/evidence/sys/power/mem_sleep"
check() {
    local expected="$1" rc=0
    bash "$root/scripts/suspend-diagnostics.sh" --check > "$t/log" 2>&1 || rc=$?
    [[ "$rc" == "$expected" ]] || { cat "$t/log"; echo "FAIL exit $rc expected $expected"; exit 1; }
}
check 0
printf 's2idle [deep]\n' > "$t/evidence/sys/power/mem_sleep"
check 1
rm -- "$t/evidence/sys/power/mem_sleep"
check 3
printf '[s2idle]\n' > "$t/evidence/sys/power/mem_sleep"
bash "$root/scripts/suspend-diagnostics.sh" > "$t/log"
grep -q 'state written to' "$t/log"
[[ $(find "$t/output" -name '*-pre.txt' | wc -l) == 1 ]]
# Git Bash may not implement real symlinks; Linux CI must execute this case.
if ln -s "$t/output" "$t/link" && [[ -L "$t/link" ]]; then
    SUSPEND_DIAG_DIR="$t/link" check 1
else
    echo 'SKIP real symlink semantics unavailable'
fi
if [[ "$(uname -s)" == Linux ]]; then
    chmod 777 "$t/output"
    check 1
fi
echo 'PASS suspend diagnostics fixture suite (no suspend)'
