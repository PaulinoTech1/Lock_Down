#!/usr/bin/env bash
# Authenticate a kernel.org tarball, then prepare a NEW source tree.
# Exit 0 PASS; 1 FAIL; 2 usage; 3 UNKNOWN. No network, patching or compilation.
set -euo pipefail
umask 077
version='' archive='' digest='' signature='' keyring='' fingerprint='' dest='' config='' localversion=''
die() { echo "FAIL $*" >&2; exit 1; }
while (( $# )); do
    [[ $# -ge 2 ]] || { echo 'usage: see docs/TOOLING_INTEGRITY.md' >&2; exit 2; }
    case "$1" in
        --version) version="$2";; --archive) archive="$2";; --sha256) digest="$2";;
        --signature) signature="$2";; --keyring) keyring="$2";; --fingerprint) fingerprint="${2^^}";;
        --source-dir) dest="$2";; --config) config="$2";; --localversion) localversion="$2";;
        --patch-manifest) echo 'UNKNOWN patch series verification unsupported; refusing' >&2; exit 3;;
        *) echo "unknown option: $1" >&2; exit 2;;
    esac
    shift 2
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || die 'explicit version and SHA-256 required'
[[ "$fingerprint" =~ ^[A-F0-9]{40}$ || "$fingerprint" =~ ^[A-F0-9]{64}$ ]] || { echo 'UNKNOWN expected signer fingerprint missing/invalid'; exit 3; }
[[ "$localversion" =~ ^-[A-Za-z0-9._+-]+$ ]] || die 'explicit LOCALVERSION required'
[[ "$(basename -- "$archive")" == "linux-$version.tar.xz" ]] || die 'archive name/version mismatch'
[[ "$(basename -- "$dest")" == "linux-$version" && "$dest" == /* ]] || die 'source directory/version mismatch'
[[ ! -e "$dest" && ! -L "$dest" ]] || die 'existing source tree refused (dirty/stale state not trusted)'
# shellcheck source=scripts/safe-directory.sh
source "$(dirname "${BASH_SOURCE[0]}")/safe-directory.sh"
safe_directory "$(dirname -- "$dest")" || die 'unsafe source parent'
for f in "$archive" "$signature" "$keyring" "$config"; do [[ -f "$f" && -r "$f" ]] || die 'missing input file'; done
[[ $(grep -c '^CONFIG_LOCALVERSION=' "$config") == 1 ]] || die 'ambiguous LOCALVERSION'
grep -Fxq "CONFIG_LOCALVERSION=\"$localversion\"" "$config" || die 'incorrect LOCALVERSION'
grep -Fxq '# CONFIG_LOCALVERSION_AUTO is not set' "$config" || die 'LOCALVERSION_AUTO must be disabled'
! grep -q '^CONFIG_LOCALVERSION_AUTO=' "$config" || die 'contradictory automatic suffix'
for tool in gpg xz tar sha256sum make; do command -v "$tool" >/dev/null || { echo "UNKNOWN missing $tool"; exit 3; }; done
stage="$(mktemp -d "$(dirname -- "$dest")/.source-check.XXXXXXXX")"
# Preserve failed evidence; no recursive deletion or reuse of old trees.
trap 'echo "INFO verification staging retained: $stage" >&2' EXIT
cp -- "$archive" "$stage/archive.tar.xz"
cp -- "$signature" "$stage/archive.sign"
cp -- "$keyring" "$stage/trusted.gpg"
actual="$(sha256sum -- "$stage/archive.tar.xz" | cut -d' ' -f1)"
[[ "$actual" == "${digest,,}" ]] || die 'archive hash mismatch'
mkdir "$stage/gnupg"
if ! xz -cd -- "$stage/archive.tar.xz" | gpg --batch --no-options --homedir "$stage/gnupg" \
    --no-default-keyring --keyring "$stage/trusted.gpg" --no-auto-key-retrieve \
    --status-fd 1 --verify "$stage/archive.sign" - > "$stage/status" 2> "$stage/gpg.log"; then
    die 'detached signature verification failed'
fi
# Pin the actual signing key fingerprint, not a user ID or short key ID.
if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|KEYREVOKED|FAILURE|ERROR)( |$)' "$stage/status"; then
    die 'invalid, expired or revoked signature/key status'
fi
[[ $(grep -c '^\[GNUPG:\] VALIDSIG ' "$stage/status") == 1 ]] || die 'ambiguous/missing verified signer'
actual_signer="$(awk '$2 == "VALIDSIG" {print $3}' "$stage/status")"
[[ "$actual_signer" == "$fingerprint" ]] || die 'unexpected signer fingerprint'
echo 'PASS archive digest and cryptographic signer'
# Restrict member spelling so GNU tar's verbose metadata can be parsed safely.
export LC_ALL=C
tar --quoting-style=literal -tJf "$stage/archive.tar.xz" > "$stage/names"
while IFS= read -r name; do
    [[ "$name" =~ ^[A-Za-z0-9_./+@=,-]+$ && "$name" == "linux-$version/"* && "$name" != *'/../'* && "$name" != *'/./'* && "$name" != */.. && "$name" != */. ]] || die 'unsafe archive member'
done < "$stage/names"
tar --quoting-style=literal --full-time --numeric-owner -tvJf "$stage/archive.tar.xz" > "$stage/types"
: > "$stage/link-names"
: > "$stage/links"
while read -r mode owner size day time member arrow target extra; do
    case "$mode" in
        [-d]*) [[ -z "$arrow" ]] || die 'unrecognized archive metadata';;
        l*)
            [[ "$arrow" == '->' && -z "$extra" && "$target" =~ ^[A-Za-z0-9_./+@=,-]+$ && "$target" != /* ]] || die 'unsafe link metadata'
            printf '%s\n' "$member" >> "$stage/link-names"
            printf '%s\t%s\n' "$member" "$target" >> "$stage/links";;
        *) die 'archive hardlinks/special files unsupported';;
    esac
done < "$stage/types"
mkdir "$stage/extracted"
# Extract regular files first, with NO archive symlinks present during writes.
tar -xJf "$stage/archive.tar.xz" --no-same-owner --no-same-permissions --keep-old-files \
    --no-wildcards --exclude-from="$stage/link-names" -C "$stage/extracted"
src="$stage/extracted/linux-$version"
while IFS=$'\t' read -r member target; do
    link="$stage/extracted/$member"
    parent="$(dirname -- "$link")"
    [[ "$(realpath -e "$parent")" == "$parent" ]] || die 'symlink or missing link parent'
    resolved="$(realpath -m -- "$parent/$target")" || die 'invalid link target'
    [[ "$resolved" == "$src" || "$resolved" == "$src/"* ]] || die 'link escapes source tree'
    ln -s -- "$target" "$link"
    [[ -L "$link" ]] || die 'filesystem does not support source symlinks'
done < "$stage/links"
# Recheck after all links exist to catch chained escapes or loops.
while IFS=$'\t' read -r member target; do
    resolved="$(realpath -m -- "$stage/extracted/$member")" || die 'invalid chained link'
    [[ "$resolved" == "$src" || "$resolved" == "$src/"* ]] || die 'chained link escapes source tree'
done < "$stage/links"
[[ -f "$src/Makefile" && ! -e "$src/.config" && ! -e "$src/include/generated" && ! -e "$src/.git" ]] || die 'source layout or freshness invalid'
[[ -z "$(find "$src" -type f \( -name '*.o' -o -name '*.cmd' -o -name vmlinux -o -name autoconf.h \) -print -quit)" ]] || die 'generated build artifacts in archive'
# No make runs before authentication/freshness checks.
actual_version="$(env -u MAKEFLAGS -u MFLAGS -u GNUMAKEFLAGS -u MAKEFILES -u KBUILD_OUTPUT \
    -u KBUILD_SRC -u KERNELRELEASE make -s --no-print-directory -C "$src" kernelversion)"
[[ "$actual_version" == "$version" ]] || die 'make kernelversion mismatch'
[[ ! -e "$dest" && ! -L "$dest" ]] || die 'destination appeared during verification'
mv -T -- "$src" "$dest"
printf 'PASS source %s version=%s archive_sha256=%s signer=%s\n' "$dest" "$version" "$actual" "$actual_signer"
echo 'NOT_APPLICABLE patch series (pristine upstream only)'
echo 'UNKNOWN kernelrelease until config resolution; build wrapper must check it before compilation'
