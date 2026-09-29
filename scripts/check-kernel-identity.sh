#!/usr/bin/env bash
# Validate the config and make kernelrelease result before compilation.
set -euo pipefail
[[ $# == 4 ]] || { echo 'usage: check-kernel-identity.sh CONFIG VERSION LOCALVERSION KERNELRELEASE' >&2; exit 2; }
config="$1" version="$2" localversion="$3" release="$4"
[[ -r "$config" ]] || exit 1
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$localversion" =~ ^-[A-Za-z0-9._+-]+$ ]] || exit 1
[[ $(grep -c '^CONFIG_LOCALVERSION=' "$config") == 1 ]] || { echo 'FAIL ambiguous LOCALVERSION'; exit 1; }
grep -Fxq "CONFIG_LOCALVERSION=\"$localversion\"" "$config" || { echo 'FAIL LOCALVERSION mismatch'; exit 1; }
grep -Fxq '# CONFIG_LOCALVERSION_AUTO is not set' "$config" || { echo 'FAIL automatic suffix not disabled'; exit 1; }
! grep -q '^CONFIG_LOCALVERSION_AUTO=' "$config" || { echo 'FAIL contradictory automatic suffix'; exit 1; }
[[ "$release" == "$version$localversion" ]] || { echo 'FAIL make kernelrelease mismatch'; exit 1; }
echo "PASS kernel identity $release"
