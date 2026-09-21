#!/usr/bin/env bash
#
# sign-kernel.sh - Sign a kernel image and its modules with a user-supplied key.
#
# This script signs; it never generates keys. Keys are generated offline on
# encrypted media per docs/SECURE_BOOT.md (Phase B) and are never stored in
# this repository. This script refuses to operate on paths inside the repo.
#
# Requires: sbsign (from sbsigntool), sign-file (from the kernel build tree
# or kernel source scripts/sign-file), sbverify (optional but used for the
# post-sign verification step).
#
# Usage:
#   sign-kernel.sh --key <private-key> --cert <certificate> \
#                  --kernel <vmlinuz> --modules-dir <dir> [--force] [--dry-run]
#
set -euo pipefail

KEY=""
CERT=""
KERNEL=""
MODULES_DIR=""
FORCE=0
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: sign-kernel.sh --key <private-key> --cert <certificate> \
       --kernel <vmlinuz> --modules-dir <dir> [--force] [--dry-run]

  --key          Private signing key (PEM). Never stored in the repo.
  --cert         Signing certificate (PEM or DER).
  --kernel       Kernel image (vmlinuz) to sign with sbsign.
  --modules-dir  Directory tree of kernel modules (.ko) to sign with sign-file.
  --force        Allow overwriting existing signatures.
  --dry-run      Print what would be done; change nothing.

The script refuses to run if the key or cert is missing, refuses targets
located inside this repository, and verifies signatures after signing.
EOF
}

# Resolve the repo root (parent of this script's directory) so we can
# refuse to touch anything inside it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

in_repo() {
    # True if $1 resolves to a path inside the repo.
    local p
    p="$(readlink -m -- "$1" 2>/dev/null || printf '%s' "$1")"
    case "$p" in
        "$REPO_ROOT"/*) return 0 ;;
        *) return 1 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --key)         KEY="${2:?--key needs a value}"; shift 2 ;;
        --cert)        CERT="${2:?--cert needs a value}"; shift 2 ;;
        --kernel)      KERNEL="${2:?--kernel needs a value}"; shift 2 ;;
        --modules-dir) MODULES_DIR="${2:?--modules-dir needs a value}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown argument: $1 (see --help)" ;;
    esac
done

[ -n "$KEY" ]         || die "--key is required"
[ -n "$CERT" ]        || die "--cert is required"
[ -n "$KERNEL" ]      || die "--kernel is required"
[ -n "$MODULES_DIR" ] || die "--modules-dir is required"

[ -f "$KEY" ]         || die "key not found or not a file: $KEY"
[ -f "$CERT" ]        || die "cert not found or not a file: $CERT"
[ -f "$KERNEL" ]      || die "kernel image not found or not a file: $KERNEL"
[ -d "$MODULES_DIR" ] || die "modules dir not found or not a directory: $MODULES_DIR"

# Never generate keys into, or sign targets inside, the repo.
for target in "$KEY" "$CERT" "$KERNEL" "$MODULES_DIR"; do
    if in_repo "$target"; then
        die "refusing to operate on a path inside the repository: $target"
    fi
done

# Locate sign-file: prefer a caller-supplied SIGN_FILE env, else search PATH.
SIGN_FILE_BIN="${SIGN_FILE:-}"
if [ -z "$SIGN_FILE_BIN" ]; then
    SIGN_FILE_BIN="$(command -v sign-file || true)"
fi
[ -n "$SIGN_FILE_BIN" ] || die "sign-file not found (set SIGN_FILE env or install kernel build tools)"

for tool in sbsign sbverify; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool missing: $tool (install sbsigntool)"
done

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN: would sign kernel image:\n  %s\n' "$KERNEL"
    printf 'DRY RUN: with key %s and cert %s\n' "$KEY" "$CERT"
    printf 'DRY RUN: would sign modules under:\n  %s\n' "$MODULES_DIR"
    printf 'DRY RUN: using sign-file at %s\n' "$SIGN_FILE_BIN"
    mapfile -t kos < <(find "$MODULES_DIR" -type f -name '*.ko' | sort)
    printf 'DRY RUN: %d module(s) found\n' "${#kos[@]}"
    exit 0
fi

# Refuse to overwrite existing signatures unless --force was given.
if sbverify --list "$KERNEL" >/dev/null 2>&1; then
    if [ "$FORCE" -eq 0 ]; then
        die "kernel image already carries a signature; re-run with --force to replace it"
    fi
    printf 'WARNING: replacing existing kernel image signature (--force)\n' >&2
fi

printf 'Signing kernel image: %s\n' "$KERNEL"
sbsign --key "$KEY" --cert "$CERT" --output "$KERNEL.signed" "$KERNEL"
mv -- "$KERNEL.signed" "$KERNEL"

printf 'Verifying kernel image signature...\n'
sbverify --cert "$CERT" "$KERNEL"
printf 'Kernel image signature OK: %s\n' "$KERNEL"

mapfile -t kos < <(find "$MODULES_DIR" -type f -name '*.ko' | sort)
printf 'Signing %d module(s) under %s\n' "${#kos[@]}" "$MODULES_DIR"

signed=0
skipped=0
for ko in "${kos[@]}"; do
    # Detect an existing signature by asking sign-file's companion check:
    # a module with a ~Module signature~ section already signed.
    if grep -q -a '~Module signature appended~' "$ko" 2>/dev/null; then
        if [ "$FORCE" -eq 0 ]; then
            printf '  SKIP (already signed, use --force to re-sign): %s\n' "$ko"
            skipped=$((skipped + 1))
            continue
        fi
        printf '  WARNING: re-signing (--force): %s\n' "$ko" >&2
    fi
    "$SIGN_FILE_BIN" sha512 "$KEY" "$CERT" "$ko"
    signed=$((signed + 1))
done

printf 'Modules signed: %d, skipped (already signed): %d\n' "$signed" "$skipped"

# Post-sign verification: every module must now carry an appended signature.
printf 'Verifying module signatures...\n'
bad=0
for ko in "${kos[@]}"; do
    if ! grep -q -a '~Module signature appended~' "$ko" 2>/dev/null; then
        printf '  FAIL: no appended signature: %s\n' "$ko"
        bad=$((bad + 1))
    fi
done
if [ "$bad" -gt 0 ]; then
    die "$bad module(s) failed post-sign verification"
fi

printf 'All %d module(s) verified with appended signatures.\n' "${#kos[@]}"
printf 'Done. Signed kernel: %s\n' "$KERNEL"
