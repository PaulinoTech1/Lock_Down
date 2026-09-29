#!/usr/bin/env bash
# Compare image packages to the exact resolved config and compiled image.
set -euo pipefail
umask 077
[[ $# -ge 5 ]] || exit 2
release="$1" config="$2" image="$3" work="$4"
shift 4
[[ "$release" =~ ^[A-Za-z0-9._+-]+$ && -f "$config" && -f "$image" ]] || exit 1
# shellcheck source=scripts/safe-directory.sh
source "$(dirname "${BASH_SOURCE[0]}")/safe-directory.sh"
safe_directory "$work" || { echo 'FAIL unsafe package verification parent'; exit 1; }
images=0
for package in "$@"; do
    [[ -f "$package" && ! -L "$package" ]] || exit 1
    name="$(dpkg-deb -f "$package" Package)"
    if [[ "$name" == "linux-image-$release" ]]; then
        images=$((images + 1))
        verify="$(mktemp -d "$work/package-check.XXXXXXXX")"
        dpkg-deb -x "$package" "$verify"
        for file in "config-$release" "vmlinuz-$release"; do
            [[ -f "$verify/boot/$file" && ! -L "$verify/boot/$file" ]] || exit 1
        done
        cmp -- "$config" "$verify/boot/config-$release" || { echo 'FAIL package/config mismatch'; exit 1; }
        cmp -- "$image" "$verify/boot/vmlinuz-$release" || { echo 'FAIL package/image mismatch'; exit 1; }
        [[ -z "$(find "$verify" -name '*.ko*' -print -quit)" ]] || { echo 'FAIL module payload'; exit 1; }
    elif [[ "$name" == linux-image-* ]]; then
        echo 'FAIL unexpected image release'; exit 1
    fi
done
[[ "$images" == 1 ]] || { echo 'FAIL expected one image package'; exit 1; }
echo 'PASS exact package/config/image identity'
