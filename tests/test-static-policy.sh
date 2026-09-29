#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
printf 'CONFIG_EXAMPLE=y\n' > "$t/config"
bash "$root/scripts/check-kconfig-duplicates.sh" "$t/config"
printf '# CONFIG_EXAMPLE is not set\n' >> "$t/config"
if bash "$root/scripts/check-kconfig-duplicates.sh" "$t/config"; then exit 1; fi
printf 'CONFIG_EXAMPLE=y\nCONFIG_EXAMPLE=y\n' > "$t/config"
if bash "$root/scripts/check-kconfig-duplicates.sh" "$t/config"; then exit 1; fi
candidate="$root/config/candidate-6.18.53-lockdown-t14g3-audit10.config"
sed '/^CONFIG_DM_CRYPT=y$/d' "$candidate" > "$t/config"
if bash "$root/scripts/preflight-check.sh" "$t/config" > "$t/log"; then exit 1; fi
sed 's/^CONFIG_IRQ_REMAP=y$/# CONFIG_IRQ_REMAP is not set/' "$candidate" > "$t/config"
if bash "$root/scripts/preflight-security.sh" "$t/config" > "$t/log" 2>&1; then exit 1; fi
sed 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-wrong"/' "$candidate" > "$t/config"
if bash "$root/scripts/check-kernel-identity.sh" "$t/config" 6.18.53 -lockdown-t14g3-audit10 6.18.53-lockdown-t14g3-audit10; then exit 1; fi
printf 'if [[ broken\n' > "$t/firmware.conf"
if bash -n "$t/firmware.conf" 2>/dev/null; then exit 1; fi
mkdir "$t/scan" "$t/scan/scripts"
printf '#!/bin/bash\necho safe\n' > "$t/scan/scripts/safe.sh"
bash "$root/scripts/check-static-safety.sh" "$t/scan"
printf 'nvme %s /dev/fixture\n' format > "$t/scan/scripts/unsafe.sh"
if bash "$root/scripts/check-static-safety.sh" "$t/scan" > "$t/log"; then exit 1; fi
rm "$t/scan/scripts/unsafe.sh"
printf '%s%s\n' '-----BEGIN ' 'PRIVATE KEY-----' > "$t/scan/secret-fixture"
if bash "$root/scripts/check-static-safety.sh" "$t/scan" > "$t/log"; then exit 1; fi
! grep -q 'BEGIN' "$t/log"
echo 'PASS static policy negative fixtures'
