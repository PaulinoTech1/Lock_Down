#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
printf 'CONFIG_LOCALVERSION="-fixture"\n# CONFIG_LOCALVERSION_AUTO is not set\n' > "$t/config"
bash "$root/scripts/check-kernel-identity.sh" "$t/config" 6.18.53 -fixture 6.18.53-fixture
for release in 6.18.52-fixture 6.18.53-wrong; do
    if bash "$root/scripts/check-kernel-identity.sh" "$t/config" 6.18.53 -fixture "$release"; then exit 1; fi
done
printf 'CONFIG_LOCALVERSION="-wrong"\n' >> "$t/config"
if bash "$root/scripts/check-kernel-identity.sh" "$t/config" 6.18.53 -fixture 6.18.53-fixture; then exit 1; fi
echo 'PASS build identity fixtures'
