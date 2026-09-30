# Two-domain egress guard: offline candidate

`offline.nft` is a repository template for `SAFE_OFFLINE`, `GUEST_EGRESS`,
`TRANSITION`, and `ERROR`. It creates dedicated `inet` and `bridge` tables and
denies host non-loopback IP output, external input, IP forwarding, and bridge
forwarding. It never flushes the full ruleset. A later, separately tested
maintenance transaction must allow only a verified MT7921U interface under an
expiring lease; that transaction is not present yet.

The template is **not installed on the ThinkPad**. It is deliberately
independent of the historical `nftables/workstation.nft`, which globally
flushes rules and permits host output. Loading both without a reviewed single
ownership plan would be unsafe. The template does not disable existing NAT or
masquerade rules, NetworkManager autoconnect, raw L2 traffic, or unapproved
physical NICs; the verifier must reject those conditions independently.

The Linux CI fixture uses a disposable network namespace to load this file
and probe IPv4/IPv6 host output. It does not prove boot ordering, USB handoff,
or physical-host behavior. Before live installation, inspect the actual
libvirt/firewalld/iptables-nft backend and hook priorities, back up current
rules, validate syntax with `nft --check -f`, and secure local-console recovery.
An nftables `drop` verdict is final across base chains, while `accept` can
still be followed by another base-chain decision; see the [nftables manual](https://netfilter.org/projects/nftables/manpage.html).
