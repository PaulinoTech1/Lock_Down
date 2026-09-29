#!/usr/bin/env bash
# Sign a digest-selected standalone EFI kernel using the existing owner model.
# Never installs or enrolls. Modular signing is fail-closed until crypto auditing exists.
set -euo pipefail
umask 077
key='' cert='' kernel='' modules='' expected='' force=0 dry=0
die() { echo "FAIL $*" >&2; exit 1; }
while (( $# )); do
    case "$1" in
        --force) force=1; shift; continue;; --dry-run) dry=1; shift; continue;;
        --help|-h) echo 'usage: sign-kernel.sh --key KEY --cert CERT --kernel IMAGE --expected-sha256 HASH [--modules-dir DIR] [--force] [--dry-run]'; exit 0;;
    esac
    [[ $# -ge 2 ]] || exit 2
    case "$1" in
        --key) key="$2";; --cert) cert="$2";; --kernel) kernel="$2";;
        --modules-dir) modules="$2";; --expected-sha256) expected="$2";;
        *) echo "unknown option $1" >&2; exit 2;;
    esac
    shift 2
done
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || die 'expected input SHA-256 required'
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for target in "$key" "$cert" "$kernel"; do
    [[ -f "$target" && ! -L "$target" ]] || die 'input must be a regular, non-symlink file'
    case "$(realpath -e -- "$target")" in "$repo"|"$repo"/*) die 'signing inputs must remain outside repository';; esac
done
# Reject a symlink in any image path component, unsafe parents and hard links.
kernel="$(realpath -s -- "$kernel")"
[[ "$kernel" == "$(realpath -e -- "$kernel")" ]] || die 'symlink image path'
# shellcheck source=scripts/safe-directory.sh
source "$repo/scripts/safe-directory.sh"
safe_directory "$(dirname -- "$kernel")" || die 'unsafe image parent'
[[ $(stat -c %h "$kernel") == 1 ]] || die 'hard-linked image refused'
if [[ -n "$modules" ]]; then
    [[ -d "$modules" && ! -L "$modules" ]] || die 'invalid modules directory'
    # Includes compressed forms and symlinks; do not silently omit them.
    if [[ -n "$(find "$modules" -name '*.ko*' -print -quit)" ]]; then
        echo 'UNKNOWN modular signing unsupported: marker/metadata is not cryptographic verification' >&2
        exit 3
    fi
fi
hash() { sha256sum -- "$1" | cut -d' ' -f1; }
[[ "$(hash "$kernel")" == "${expected,,}" ]] || die 'input digest mismatch'
for tool in sbsign sbverify; do command -v "$tool" >/dev/null || { echo "UNKNOWN missing $tool"; exit 3; }; done
if (( dry )); then echo 'NOT_APPLICABLE dry-run: no signing or replacement'; exit 0; fi
if sbverify --list "$kernel" >/dev/null 2>&1 && (( ! force )); then die 'existing signature; --force required'; fi
stage="$(mktemp -d "$(dirname -- "$kernel")/.sign-kernel.XXXXXXXX")"
trap 'rm -f -- "$stage/input" "$stage/output" "$stage/cert"; rmdir -- "$stage"' EXIT
cp -- "$kernel" "$stage/input"
cp -- "$cert" "$stage/cert"
[[ "$(hash "$stage/input")" == "${expected,,}" ]] || die 'input changed before signing'
identity="$(stat -c '%d:%i' -- "$kernel")"
sbsign --key "$key" --cert "$stage/cert" --output "$stage/output" "$stage/input"
[[ -f "$stage/output" && ! -L "$stage/output" ]] || die 'invalid signed output'
sbverify --cert "$stage/cert" "$stage/output" || die 'expected-certificate verification failed; original preserved'
[[ ! -L "$kernel" && "$(stat -c '%d:%i' -- "$kernel")" == "$identity" && "$(hash "$kernel")" == "${expected,,}" ]] || die 'original changed during signing'
chmod --reference="$kernel" "$stage/output"
mv -T -- "$stage/output" "$kernel"
printf 'PASS expected-certificate signature verified before replacement; signed_inner_image_sha256=%s\n' "$(hash "$kernel")"
echo 'INFO this verifies the supplied certificate, not MOK enrollment or package identity'
