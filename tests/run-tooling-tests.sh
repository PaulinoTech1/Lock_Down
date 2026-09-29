#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
for test in test-verify-secure-boot test-suspend-diagnostics test-kernel-source \
    test-build-identity test-build-manifest test-build-packages test-sign-kernel test-module-evidence \
    test-static-policy test-preflight-security; do
    echo "RUN $test"
    bash "tests/$test.sh"
done
rc=0
bash tests/test-crypto-integration.sh || rc=$?
[[ "$rc" == 0 || ( "$rc" == 77 && "${REQUIRE_CRYPTO:-0}" != 1 ) ]] || exit "$rc"
echo 'PASS available tooling fixtures; review explicit SKIP results above'
