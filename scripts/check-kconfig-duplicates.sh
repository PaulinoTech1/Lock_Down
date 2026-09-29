#!/usr/bin/env bash
set -euo pipefail
[[ $# -gt 0 ]] || exit 2
for file in "$@"; do
    awk '
        /^CONFIG_[A-Za-z0-9_]+=/ {split($0,a,"="); name=a[1]}
        /^# CONFIG_[A-Za-z0-9_]+ is not set$/ {name=$2}
        name != "" {if (++seen[name]>1) {print "FAIL duplicate " name " at " FILENAME ":" FNR; failed=1}; name=""}
        END {exit failed}
    ' "$file" || exit 1
done
echo 'PASS unique Kconfig assignments'
