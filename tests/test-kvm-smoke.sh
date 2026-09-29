#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test -r "$repo_dir/scripts/kvm-smoke.sh"

if bash "$repo_dir/scripts/kvm-smoke.sh" unexpected-guest-argument >/dev/null 2>&1; then
    echo 'FAIL: smoke test accepted an unexpected guest argument' >&2
    exit 1
fi

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo 'SKIP: live KVM device unavailable'
    exit 0
fi

output="$(bash "$repo_dir/scripts/kvm-smoke.sh")"
repeat_output="$(bash "$repo_dir/scripts/kvm-smoke.sh")"
printf '%s\n' "$output" "$repeat_output"

expected_release="$(uname -r)"
for result in "$output" "$repeat_output"; do
    for run in 1 2; do
        grep -Fxq "PASS run=$run release=$expected_release" <<<"$result"
    done
    grep -Fxq 'KVM smoke: PASS (2/2)' <<<"$result"
done

first_hash="$(grep -E '^initramfs_sha256=[0-9a-f]{64}$' <<<"$output")"
repeat_hash="$(grep -E '^initramfs_sha256=[0-9a-f]{64}$' <<<"$repeat_output")"
[ "$first_hash" = "$repeat_hash" ]

echo 'KVM smoke integration test: PASS'
