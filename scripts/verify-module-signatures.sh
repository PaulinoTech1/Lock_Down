#!/usr/bin/env bash
# Read-only evidence inventory. Metadata/markers NEVER establish trusted signing.
# 0 monolithic N/A; 1 unsigned evidence; 2 usage; 3 incomplete cryptographic trust.
set -euo pipefail
config="/boot/config-$(uname -r)" module=''
while (( $# )); do
    [[ $# -ge 2 ]] || exit 2
    case "$1" in --config) config="$2";; --module) module="$2";; *) exit 2;; esac
    shift 2
done
if [[ -z "$module" && -r "$config" ]] && grep -qx '# CONFIG_MODULES is not set' "$config" && ! grep -q '^CONFIG_MODULES=' "$config"; then
    echo 'NOT_APPLICABLE module signatures: supplied config is monolithic'
    exit 0
fi
files=()
if [[ -n "$module" ]]; then
    files=("$module")
else
    command -v modinfo >/dev/null || { echo 'UNKNOWN modinfo unavailable'; exit 3; }
    loaded="$(lsmod)" || { echo 'UNKNOWN loaded module list unavailable'; exit 3; }
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        path="$(modinfo -n "$name")" || { echo 'UNKNOWN module path unavailable'; exit 3; }
        files+=("$path")
    done < <(awk 'NR>1 {print $1}' <<< "$loaded")
fi
fail=0
for file in "${files[@]}"; do
    [[ -r "$file" && -f "$file" ]] || { echo 'UNKNOWN module file unavailable'; continue; }
    case "$file" in
        *.ko)
            if grep -aq '~Module signature appended~' "$file"; then
                echo "INFO marker present: $file"
            else
                echo "FAIL signature marker absent: $file"
                fail=1
            fi;;
        *.ko.xz|*.ko.zst|*.ko.gz) echo "INFO compressed module: marker not inspected: $file";;
        *) echo "UNKNOWN unsupported module representation: $file";;
    esac
    if metadata="$(modinfo -F signer "$file" 2>/dev/null)" && [[ -n "$metadata" ]]; then
        echo "INFO parseable signer metadata present: $file (not cryptographic verification)"
    else
        echo "UNKNOWN signer metadata: $file"
    fi
done
echo 'UNKNOWN cryptographic trust: no content/signature verification or kernel trust-chain validation performed'
(( fail == 0 )) || exit 1
exit 3
