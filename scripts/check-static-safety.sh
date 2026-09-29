#!/usr/bin/env bash
# Bounded regex guard, not a shell parser or proof that secrets are absent.
# Report filenames/rules only, never matched secret contents.
set -euo pipefail
[[ $# == 1 && -d "$1" ]] || exit 2
root="$1" fail=0
private='-----BEGIN (RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'
credential="(recovery[_-]?passphrase|password|passwd)[[:space:]]*[:=][[:space:]]*[\"'][^\"']+[\"']"
danger='curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh|(^|[^a-z_])mkfs(\.[a-z0-9]+)?[[:space:]]|dd[[:space:]].*of=|nvme[[:space:]]+(sanitize|format)|efibootmgr[^#]*-B|mokutil[^#]*--delete'
danger+='|tpm2_''clear'
while IFS= read -r -d '' file; do
    if grep -aEq -- "$private" "$file" || grep -aEiq -- "$credential" "$file"; then
        printf 'FAIL secret-pattern: %s (content redacted)\n' "$file"; fail=1
    fi
    case "$file" in
        */scripts/*.sh|*/tests/*.sh)
            if grep -vE '^[[:space:]]*#' "$file" | grep -E -- "$danger" >/dev/null; then
                printf 'FAIL dangerous-construct: %s\n' "$file"; fail=1
            fi;;
    esac
done < <(find "$root" -type d \( -name .git -o -name build \) -prune -o -type f -print0)
(( fail == 0 )) || exit 1
echo 'PASS bounded secret/dangerous-construct scan'
