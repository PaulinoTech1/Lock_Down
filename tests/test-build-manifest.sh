#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir "$t/bin"
for tool in gcc ld; do printf '#!/usr/bin/env bash\necho fixture-tool-1\n' > "$t/bin/$tool"; done
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" BUILD_TIMESTAMP=2026-09-29T00:00:00Z
for file in source.tar.xz requested resolved firmware pkg.deb; do printf 'fixture\n' > "$t/$file"; done
run() { bash "$root/scripts/write-build-manifest.sh" 6.18.53 6.18.53-fixture "$t/source.tar.xz" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "$t/requested" "$t/resolved" "$t/firmware" 78ff2a7814280bae74ba93b39656f4a42e92ce97 "$t/pkg.deb"; }
run > "$t/a.json"
run > "$t/b.json"
cmp "$t/a.json" "$t/b.json"
grep -q '"signed_inner_image_sha256": null' "$t/a.json"
grep -q '"kernel_release": "6.18.53-fixture"' "$t/a.json"
rm "$t/pkg.deb"
if run > "$t/b.json"; then echo 'FAIL missing artifact accepted'; exit 1; fi
echo 'PASS manifest determinism and missing-artifact fixtures'
