#!/usr/bin/env bash
# Audited monolithic build, fresh private workspace, no installation/signing.
# See docs/TOOLING_INTEGRITY.md. Inputs are explicit, never inferred from /boot.
set -euo pipefail
umask 077
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile=hardened dry=0 version='' localversion='' archive='' digest='' signature='' keyring='' signer='' base='' firmware=''
die() { echo "FAIL $*" >&2; exit 1; }
while (( $# )); do
    case "$1" in
        --dry-run) dry=1; shift; continue;;
        --help|-h) echo 'See docs/TOOLING_INTEGRITY.md for required provenance inputs.'; exit 0;;
    esac
    [[ $# -ge 2 ]] || exit 2
    case "$1" in
        --profile) profile="$2";; --version) version="$2";; --localversion) localversion="$2";;
        --archive) archive="$2";; --sha256) digest="$2";; --signature) signature="$2";;
        --keyring) keyring="$2";; --fingerprint) signer="$2";; --base-config) base="$2";;
        --firmware-dropin) firmware="$2";;
        *) echo "unknown option: $1" >&2; exit 2;;
    esac
    shift 2
done
[[ "$profile" == hardened || "$profile" == diagnostic ]] || exit 2
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$localversion" =~ ^-[A-Za-z0-9._+-]+$ ]] || die 'explicit version/LOCALVERSION required'
[[ "$digest" =~ ^[a-fA-F0-9]{64}$ && "$signer" =~ ^[a-fA-F0-9]{40}$ ]] || die 'explicit archive hash and signer fingerprint required'
for file in "$archive" "$signature" "$keyring" "$base" "$firmware"; do [[ -f "$file" && -r "$file" ]] || die 'missing provenance/config/firmware input'; done
[[ "$(basename -- "$archive")" == "linux-$version.tar.xz" ]] || die 'archive name mismatch'
# Do not claim an audit from a dirty checkout or an untracked fragment.
[[ -z "$(git -C "$repo" status --porcelain --untracked-files=normal)" ]] || die 'repository must be clean for audited builds'
commit="$(git -C "$repo" rev-parse HEAD)"
if (( dry )); then
    echo 'NOT_APPLICABLE dry-run: no authentication, make, build or filesystem changes performed'
    echo "INFO would verify $version, resolve $version$localversion and build in a new private directory"
    exit 0
fi
for tool in make gcc ld flex bison openssl gawk git xz gpg tar sha256sum dpkg-deb dpkg-query; do
    command -v "$tool" >/dev/null || die "missing tool $tool"
done
[[ -f /usr/include/openssl/ssl.h ]] || die 'missing OpenSSL build headers'
for package in debhelper libdw-dev libelf-dev; do
    [[ "$(dpkg-query -W -f='${Status}' "$package")" == 'install ok installed' ]] || die "missing $package"
done
[[ "$profile" != diagnostic ]] || command -v pahole >/dev/null || die 'missing pahole'
# No arbitrary MAKEFLAGS/LOCALVERSION/KCONFIG_CONFIG or compiler override.
unset MAKEFLAGS MFLAGS KBUILD_OUTPUT KCONFIG_CONFIG LOCALVERSION
export CC=gcc
# shellcheck source=scripts/safe-directory.sh
source "$repo/scripts/safe-directory.sh"
[[ -d "$repo/build" ]] || mkdir -- "$repo/build"
safe_directory "$repo/build" || die 'unsafe build parent'
run="$(mktemp -d "$repo/build/audited.XXXXXXXX")"
echo "INFO build workspace retained at $run"
cp -- "$archive" "$run/linux-$version.tar.xz"
cp -- "$signature" "$run/source.sign"
cp -- "$keyring" "$run/trusted.gpg"
archive="$run/linux-$version.tar.xz"
signature="$run/source.sign"
keyring="$run/trusted.gpg"
cp -- "$base" "$run/base.config"
cp -- "$firmware" "$run/firmware.conf"
cp -- "$repo/config/hardened.config" "$run/hardened.config"
cp -- "$repo/config/diagnostic.config" "$run/diagnostic.config"
# Use the reviewed fragment's release intent. No automatic rewriting.
bash "$repo/scripts/check-kernel-identity.sh" "$run/hardened.config" "$version" "$localversion" "$version$localversion"
bash -n "$run/firmware.conf"
grep -Fq "== $version$localversion ]]" "$run/firmware.conf" || die 'firmware drop-in release guard mismatch'
src="$run/linux-$version"
bash "$repo/scripts/verify-kernel-source.sh" --version "$version" --localversion "$localversion" \
    --archive "$archive" --sha256 "$digest" --signature "$signature" --keyring "$keyring" \
    --fingerprint "$signer" --source-dir "$src" --config "$run/hardened.config"
cp -- "$run/base.config" "$src/.config"
fragments=("$run/hardened.config")
[[ "$profile" != diagnostic ]] || fragments+=("$run/diagnostic.config")
env KCONFIG_CONFIG="$src/.config" bash "$src/scripts/kconfig/merge_config.sh" -m "$src/.config" "${fragments[@]}"
cp -- "$src/.config" "$run/requested.config"
make -C "$src" olddefconfig
make -C "$src" listnewconfig
release="$(make -s --no-print-directory -C "$src" kernelrelease)"
bash "$repo/scripts/check-kernel-identity.sh" "$src/.config" "$version" "$localversion" "$release"
bash "$repo/scripts/preflight-check.sh" "$src/.config"
if [[ "$profile" == hardened ]]; then bash "$repo/scripts/preflight-security.sh" "$src/.config"; fi
grep -qx '# CONFIG_MODULES is not set' "$src/.config" || die 'modular builds unsupported'
cp -- "$src/.config" "$run/resolved.config"
make -C "$src" -j"$(nproc)" bindeb-pkg
cmp -- "$run/resolved.config" "$src/.config" || die 'config changed during compilation'
[[ "$(make -s --no-print-directory -C "$src" kernelrelease)" == "$release" ]] || die 'release changed during compilation'
shopt -s nullglob
packages=("$run/"*.deb)
(( ${#packages[@]} )) || die 'no packages produced'
images=0
for package in "${packages[@]}"; do
    name="$(dpkg-deb -f "$package" Package)"
    if [[ "$name" == "linux-image-$release" ]]; then
        images=$((images + 1))
        verify="$(mktemp -d "$run/package-check.XXXXXXXX")"
        dpkg-deb -x "$package" "$verify"
        cmp -- "$run/resolved.config" "$verify/boot/config-$release" || die 'package/config mismatch'
        [[ -f "$verify/boot/vmlinuz-$release" && ! -L "$verify/boot/vmlinuz-$release" ]] || die 'missing package kernel image'
        [[ -z "$(find "$verify" -type f -name '*.ko*' -print -quit)" ]] || die 'unexpected module payload'
    elif [[ "$name" == linux-image-* ]]; then
        die 'unexpected image package release'
    fi
done
[[ "$images" == 1 ]] || die 'expected exactly one matching kernel image package'
[[ "$(sha256sum "$archive" | cut -d' ' -f1)" == "${digest,,}" ]] || die 'source archive changed'
bash "$repo/scripts/write-build-manifest.sh" "$version" "$release" "$archive" "${signer^^}" \
    "$run/requested.config" "$run/resolved.config" "$run/firmware.conf" "$commit" "${packages[@]}" > "$run/manifest.json.tmp"
mv -- "$run/manifest.json.tmp" "$run/manifest.json"
echo "PASS build provenance manifest: $run/manifest.json"
echo 'UNKNOWN signing/install/boot/hardware validation; owner review required. Prior kernels unchanged.'
