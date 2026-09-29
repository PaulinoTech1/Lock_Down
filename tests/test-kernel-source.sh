#!/usr/bin/env bash
# Synthetic source/archive plus command fixtures; never build a kernel.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir -p "$t/bin" "$t/input/linux-6.18.53" "$t/work"
printf 'VERSION = 6\nPATCHLEVEL = 18\nSUBLEVEL = 53\n' > "$t/input/linux-6.18.53/Makefile"
tar -cJf "$t/linux-6.18.53.tar.xz" -C "$t/input" linux-6.18.53
touch "$t/archive.sign" "$t/keyring.gpg"
printf 'CONFIG_LOCALVERSION="-fixture"\n# CONFIG_LOCALVERSION_AUTO is not set\n' > "$t/request.config"
cat > "$t/bin/gpg" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "[GNUPG:] VALIDSIG ${SIGNER:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA} 2026-01-01 0 0 4 0 1 10 00 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
[[ -z "${GPG_STATUS:-}" ]] || echo "[GNUPG:] $GPG_STATUS"
exit "${GPG_EXIT:-0}"
EOF
cat > "$t/bin/make" <<'EOF'
#!/usr/bin/env bash
echo called >> "$MAKE_LOG"
echo "${MAKE_VERSION:-6.18.53}"
EOF
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" MAKE_LOG="$t/make.log"
digest="$(sha256sum "$t/linux-6.18.53.tar.xz" | cut -d' ' -f1)"
run() {
    bash "$root/scripts/verify-kernel-source.sh" --version "${VERSION:-6.18.53}" \
        --archive "$t/linux-6.18.53.tar.xz" --sha256 "${HASH:-$digest}" \
        --signature "$t/archive.sign" --keyring "$t/keyring.gpg" \
        --fingerprint AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
        --source-dir "$t/work/linux-${VERSION:-6.18.53}" \
        --config "$t/request.config" --localversion "${LOCAL:--fixture}"
}
reject() {
    local rc=0
    rm -f "$MAKE_LOG"
    run > "$t/log" 2>&1 || rc=$?
    [[ "$rc" != 0 && ! -e "$MAKE_LOG" ]] || { cat "$t/log"; echo 'FAIL unsafe input reached make'; exit 1; }
}
VERSION=6.18.52 reject
HASH=0000000000000000000000000000000000000000000000000000000000000000 reject
SIGNER=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB reject
GPG_EXIT=1 reject
GPG_STATUS='EXPKEYSIG fixture expired' reject
LOCAL=-wrong reject
mkdir -p "$t/work/linux-6.18.53"
touch "$t/work/linux-6.18.53/.config"
reject # stale generated state
printf 'modified\n' > "$t/work/linux-6.18.53/Makefile"
reject # dirty source state
find "$t/work/linux-6.18.53" -depth -delete
run > "$t/log"
grep -q 'PASS source' "$t/log"
[[ -f "$t/work/linux-6.18.53/Makefile" ]]
find "$t/work/linux-6.18.53" -depth -delete
if MAKE_VERSION=6.18.52 run > "$t/log" 2>&1; then echo 'FAIL wrong make kernelversion accepted'; exit 1; fi
# Genuine source archives include symlinks. These cases require POSIX semantics.
if [[ "$(uname -s)" == Linux ]]; then
    mkdir "$t/input/linux-6.18.53/sub"
    ln -s ../Makefile "$t/input/linux-6.18.53/sub/inside"
    tar -cJf "$t/linux-6.18.53.tar.xz" -C "$t/input" linux-6.18.53
    digest="$(sha256sum "$t/linux-6.18.53.tar.xz" | cut -d' ' -f1)"
    run > "$t/log"
    [[ -L "$t/work/linux-6.18.53/sub/inside" ]]
    find "$t/work/linux-6.18.53" -depth -delete
    ln -s ../../../outside "$t/input/linux-6.18.53/sub/escape"
    tar -cJf "$t/linux-6.18.53.tar.xz" -C "$t/input" linux-6.18.53
    digest="$(sha256sum "$t/linux-6.18.53.tar.xz" | cut -d' ' -f1)"
    reject
else
    echo 'SKIP source symlink semantics require Linux'
fi
echo 'PASS source provenance fixture suite'
