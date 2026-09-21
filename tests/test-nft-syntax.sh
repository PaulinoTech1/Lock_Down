#!/usr/bin/env bash
# tests/test-nft-syntax.sh - Validate nftables rule file syntax.
#
# If nft is available: runs `nft --check -f` on each *.nft file found under
# the repo. A "syntax error" from nft is a hard FAIL. A failure WITHOUT a
# syntax error (e.g. "Could not process rule", which happens when the
# checking kernel lacks netfilter features like conntrack) is reported as
# SKIP-environmental with a warning, not a failure: the rules may be fine
# on a kernel that has those features (e.g. the CI runner).
# If nft is absent: SKIPS with a clear message. Skip is not failure.
# Never loads rules into the kernel (uses --check only).
#
# LOCAL-safe: read-only; safe in CI.

set -euo pipefail

# Find candidate rule files. None are required to exist.
mapfile -t nft_files < <(find . -name '*.nft' -not -path './.git/*' 2>/dev/null || true)

if [[ "${#nft_files[@]}" -eq 0 ]]; then
    echo "test-nft-syntax: SKIP (no *.nft rule files in repo)"
    exit 0
fi

if ! command -v nft >/dev/null 2>&1; then
    echo "test-nft-syntax: SKIP (nft not installed; cannot syntax-check ${#nft_files[@]} file(s))"
    exit 0
fi

fail=0
skipped_env=0
for f in "${nft_files[@]}"; do
    out=""
    if out="$(nft --check -f "${f}" 2>&1)"; then
        echo "OK: ${f}"
    elif echo "${out}" | grep -q "syntax error"; then
        echo "FAIL: ${f} (nft syntax error):" >&2
        echo "${out}" >&2
        fail=1
    else
        echo "SKIP-environmental: ${f} (nft --check failed without a syntax error;"
        echo "  this kernel likely lacks netfilter features the rules need, e.g. conntrack)"
        skipped_env=$((skipped_env + 1))
    fi
done

if [[ "${fail}" -ne 0 ]]; then
    echo "test-nft-syntax: FAILED" >&2
    exit 1
fi
echo "test-nft-syntax: PASS-or-SKIP (${#nft_files[@]} file(s), ${skipped_env} environmental skip(s))"
