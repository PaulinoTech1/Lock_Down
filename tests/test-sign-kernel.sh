#!/usr/bin/env bash
# Command doubles test ordering/atomic replacement, not real cryptography.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir "$t/bin" "$t/modules"
printf fixture-key > "$t/key"
printf fixture-cert > "$t/cert"
printf original > "$t/image"
cat > "$t/bin/sbsign" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do
    case "$1" in --output) out="$2"; shift 2;; --key|--cert) shift 2;; *) input="$1"; shift;; esac
done
cat "$input" > "$out"
printf signed >> "$out"
EOF
cat > "$t/bin/sbverify" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --list ]]; then
    if [[ "${LIST_UNKNOWN:-0}" == 1 ]]; then
        echo 'image signature inspection failed' >&2
        exit 1
    fi
    if [[ "${LIST_SIGNED:-0}" == 1 ]]; then
        echo 'signature 1'
    else
        echo 'No signature table present'
    fi
    exit 0
fi
[[ "${VERIFY_FAIL:-0}" == 0 ]] || exit 1
grep -q signed "${@: -1}"
EOF
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH"
hash="$(sha256sum "$t/image" | cut -d' ' -f1)"
run() { bash "$root/scripts/sign-kernel.sh" --key "$t/key" --cert "$t/cert" --kernel "$t/image" --modules-dir "$t/modules" --expected-sha256 "$hash"; }
if VERIFY_FAIL=1 run > "$t/log" 2>&1; then echo 'FAIL verification failure accepted'; exit 1; fi
[[ $(cat "$t/image") == original ]]
printf sentinel > "$t/image.signed"
run > "$t/log"
[[ $(cat "$t/image") == originalsigned && $(cat "$t/image.signed") == sentinel ]]
printf original > "$t/image"
if LIST_SIGNED=1 run > "$t/log" 2>&1; then echo 'FAIL existing signature accepted'; exit 1; fi
[[ $(cat "$t/image") == original ]]
if LIST_UNKNOWN=1 run > "$t/log" 2>&1; then echo 'FAIL unknown signature state accepted'; exit 1; fi
[[ $(cat "$t/image") == original ]]
for suffix in ko ko.xz ko.zst ko.gz; do
    touch "$t/modules/fixture.$suffix"
    if run > "$t/log" 2>&1; then echo 'FAIL unverified modules accepted'; exit 1; fi
    [[ $(cat "$t/image") == original ]]
    rm "$t/modules/fixture.$suffix"
done
hash=0000000000000000000000000000000000000000000000000000000000000000
if run > "$t/log" 2>&1; then echo 'FAIL wrong artifact accepted'; exit 1; fi
if ln -s "$t/image" "$t/linked" && [[ -L "$t/linked" ]]; then
    if bash "$root/scripts/sign-kernel.sh" --key "$t/key" --cert "$t/cert" --kernel "$t/linked" --expected-sha256 "$hash"; then exit 1; fi
else
    echo 'SKIP real symlink semantics unavailable'
fi
echo 'PASS signing ordering/identity fixtures (mock crypto)'
