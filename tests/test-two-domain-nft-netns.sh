#!/usr/bin/env bash
# Disposable Linux CI only. Creates and removes two private network namespaces.
set -euo pipefail

[[ "${LOCKDOWN_DISPOSABLE_CI:-}" == 1 && "${CI:-}" == true && "$(id -u)" == 0 ]] || {
    echo 'This fixture requires root in disposable CI; refusing to touch host networking.' >&2
    exit 77
}
command -v nft >/dev/null
command -v ip >/dev/null
command -v ping >/dev/null

repo="$(cd "$(dirname "$0")/.." && pwd)"
first="ld-a-$$"
second="ld-b-$$"
cleanup() {
    ip netns del "$first" 2>/dev/null || true
    ip netns del "$second" 2>/dev/null || true
}
trap cleanup EXIT

ip netns add "$first"
ip netns add "$second"
ip link add "vda$$" type veth peer name "vdb$$"
ip link set "vda$$" netns "$first"
ip link set "vdb$$" netns "$second"
ip -n "$first" link set lo up
ip -n "$second" link set lo up
ip -n "$first" addr add 192.0.2.1/24 dev "vda$$"
ip -n "$second" addr add 192.0.2.2/24 dev "vdb$$"
ip -n "$first" -6 addr add 2001:db8::1/64 dev "vda$$" nodad
ip -n "$second" -6 addr add 2001:db8::2/64 dev "vdb$$" nodad
ip -n "$first" link set "vda$$" up
ip -n "$second" link set "vdb$$" up

ip netns exec "$first" ping -q -c 1 -W 2 192.0.2.2 >/dev/null
ip netns exec "$first" ping -6 -q -c 1 -W 2 2001:db8::2 >/dev/null
ip netns exec "$first" nft --check -f "$repo/nftables/two-domain/offline.nft"
ip netns exec "$first" nft -f "$repo/nftables/two-domain/offline.nft"

if ip netns exec "$first" ping -q -c 1 -W 1 192.0.2.2 >/dev/null 2>&1; then
    echo 'FAIL: IPv4 output escaped offline guard' >&2
    exit 1
fi
if ip netns exec "$first" ping -6 -q -c 1 -W 1 2001:db8::2 >/dev/null 2>&1; then
    echo 'FAIL: IPv6 output escaped offline guard' >&2
    exit 1
fi

# Another base chain's accept cannot override the guard's drop.
ip netns exec "$first" nft add table inet permissive
ip netns exec "$first" nft 'add chain inet permissive output { type filter hook output priority 0; policy accept; }'
if ip netns exec "$first" ping -q -c 1 -W 1 192.0.2.2 >/dev/null 2>&1; then
    echo 'FAIL: permissive chain overrode guard' >&2
    exit 1
fi

# A rejected transaction must leave the previous guard installed.
if printf '%s\n' 'delete table inet lockdown_guard' 'this-is-invalid' |
    ip netns exec "$first" nft -f - >/dev/null 2>&1; then
    echo 'FAIL: invalid transaction was accepted' >&2
    exit 1
fi
ip netns exec "$first" nft list table inet lockdown_guard >/dev/null
if ip netns exec "$first" ping -q -c 1 -W 1 192.0.2.2 >/dev/null 2>&1; then
    echo 'FAIL: failed transaction removed guard' >&2
    exit 1
fi

echo 'PASS: disposable IPv4/IPv6 output, accept coexistence, and failed transaction'
