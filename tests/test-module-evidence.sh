#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir "$t/bin"
printf '#!/usr/bin/env bash\necho fixture-metadata\n' > "$t/bin/modinfo"
chmod +x "$t/bin/modinfo"
export PATH="$t/bin:$PATH"
printf '# CONFIG_MODULES is not set\n' > "$t/config"
bash "$root/scripts/verify-module-signatures.sh" --config "$t/config" > "$t/log"
grep -q NOT_APPLICABLE "$t/log"
printf unsigned > "$t/test.ko"
rc=0
bash "$root/scripts/verify-module-signatures.sh" --module "$t/test.ko" > "$t/log" || rc=$?
[[ "$rc" == 1 ]]
printf '~Module signature appended~\n' >> "$t/test.ko"
rc=0
bash "$root/scripts/verify-module-signatures.sh" --module "$t/test.ko" > "$t/log" || rc=$?
[[ "$rc" == 3 ]]
grep -q 'UNKNOWN.*trust' "$t/log"
! grep -q '^PASS' "$t/log"
gzip -c "$t/test.ko" > "$t/test.ko.gz"
rc=0
bash "$root/scripts/verify-module-signatures.sh" --module "$t/test.ko.gz" > "$t/log" || rc=$?
[[ "$rc" == 3 ]]
echo 'PASS module marker/metadata never promoted to cryptographic trust'
