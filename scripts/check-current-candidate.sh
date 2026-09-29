#!/usr/bin/env bash
# Data descriptor is parsed, never sourced as shell code.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
descriptor="${1:-$repo/config/current-candidate.txt}"
declare -A values=()
while IFS='=' read -r key value; do
    [[ -n "$key" && "$key" != \#* ]] || continue
    case "$key" in config|firmware|version|localversion) ;; *) echo 'FAIL unknown candidate key'; exit 1;; esac
    [[ -z "${values[$key]+set}" && -n "$value" ]] || { echo 'FAIL duplicate/empty candidate key'; exit 1; }
    values[$key]="$value"
done < "$descriptor"
for key in config firmware version localversion; do [[ -n "${values[$key]:-}" ]] || exit 1; done
for key in config firmware; do
    [[ "${values[$key]}" =~ ^config/[A-Za-z0-9._-]+$ ]] || exit 1
done
config="$repo/${values[config]}" firmware="$repo/${values[firmware]}"
release="${values[version]}${values[localversion]}"
bash "$repo/scripts/check-kconfig-duplicates.sh" "$config"
bash "$repo/scripts/check-kernel-identity.sh" "$config" "${values[version]}" "${values[localversion]}" "$release"
bash -n "$firmware"
grep -Fq "== $release ]]" "$firmware" || { echo 'FAIL firmware release guard'; exit 1; }
for script in scripts/preflight-check.sh scripts/preflight-security.sh \
    lock-down-kernel/scripts/validate-boot-critical.sh tests/test-audit8-media-config.sh \
    tests/test-audit9-device-config.sh tests/test-audit10-usb-config.sh; do
    bash "$repo/$script" "$config"
done
bash "$repo/lock-down-kernel/scripts/audit-config.sh" --project-root "$repo" --config "$config"
echo 'PASS current candidate static gates; no hardware validation'
