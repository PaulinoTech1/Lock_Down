#!/usr/bin/env bash
# Same bounded Markdown link syntax as the original CI check, without /tmp markers.
set -euo pipefail
fail=0
while IFS= read -r -d '' file; do
    while IFS= read -r target; do
        case "$target" in http://*|https://*|mailto:*|\#*) continue;; esac
        target="${target%%#*}"
        [[ -n "$target" ]] || continue
        if [[ ! -e "$(dirname "$file")/$target" ]]; then
            echo "FAIL missing relative link in $file: $target"; fail=1
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(find docs vm-profiles lock-down-kernel -name '*.md' -print0)
(( fail == 0 )) || exit 1
echo 'PASS relative documentation links'
