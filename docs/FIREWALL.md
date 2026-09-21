# Firewall (nftables)

Purpose: give the workstation a simple, auditable packet filter so that nothing on the network can reach services that were never meant to be reachable, and so that outbound expectations are at least documented.

Status: RECOMMENDED. Confidence: High on nftables as the interface; Medium on any given ruleset surviving a real desktop's needs until tested.

## Design principles

- nftables is the primary and only interface. No legacy iptables commands, no iptables-to-nftables translation shims. One syntax to learn, one ruleset to read.
- Conservative default: DROP unsolicited inbound. The machine initiates connections; the network does not initiate them.
- Auditable simplicity over cleverness. A short ruleset you can read in one sitting beats a clever one that nobody can verify. Prefer explicit accept rules for named services over dynamic tricks.
- Everything that is not explicitly allowed inbound is dropped. Logging of dropped inbound is kept minimal (rate-limited) to avoid log flooding.

## Baseline policy

- input: default DROP. Accept: established/related return traffic, loopback, ICMPv6 necessities (neighbor discovery, echo for path MTU), DHCPv6 client traffic needed for address assignment. DHCPv4 client traffic is needed too; document where it is allowed and why.
- forward: default DROP. VM traffic is handled in a dedicated zone chain (see below).
- output: default ACCEPT (workstation posture; a restrictive egress policy is a separate project and is OPTIONAL, not required here).

## DHCP and DNS

- DHCP must keep working or the machine loses its address. Allow UDP 67/68 (v4) and the v6 client/server ports explicitly, tied to the expected interface role, not to the world.
- DNS is outbound to the configured resolvers. No inbound DNS listener is expected on a workstation.

## Host vs libvirt VM zones

The workstation runs libvirt with a NAT network (`virbr0`). Separation rules:

- Host input chain treats `virbr0` as untrusted inbound: traffic FROM VMs to the HOST is dropped unless explicitly allowed (e.g. a documented DNS/DHCP service the NAT network provides).
- VM-to-VM and VM-to-internet traffic flows through the forward chain in a dedicated `vm` zone chain so host rules stay readable.
- Management services on the host (libvirt's own API socket is local-only by default; never expose it on TCP) must not be reachable from guest VMs.
- The NAT network's DHCP/DNS (dnsmasq) is the exception: allow guests to reach only those two ports on the bridge address, and document the bridge address at deployment time.

### How libvirt's default NAT interacts with host rules

libvirt installs its own iptables/nftables rules when the default network starts (forwarding, masquerade, and DHCP/DNS accepts). This project uses native nftables, so:

- Verify which backend libvirt uses on the target release (`virsh net-list`, and check whether libvirt writes iptables rules, nftables rules, or delegates to firewalld). If libvirt writes its own rules, they coexist with the host ruleset; the host ruleset must not DROP packets libvirt's own rules legitimately forward, or VM networking breaks.
- Order matters: decide once whether libvirt manages the VM zone and the host ruleset stays out of it, or whether the host ruleset owns everything and libvirt's network hooks are reviewed. Mixing both without a decision produces rules that contradict each other.
- Recommended starting point: let libvirt manage its NAT network rules, and keep the HOST input chain strict about what guests may reach. Document the libvirt rule backend observed at deployment time in this file's deployment notes.

## Explicitly enabled services

Each service gets a commented accept rule naming the service, the port, and the source scope (e.g. LAN-only, specific subnet). There are no generic "allow all from private ranges" shortcuts. See nftables/workstation.nft for the placeholder pattern.

## Limitation

- A host firewall does not protect against a compromised local process exfiltrating outbound (output is ACCEPT by design here).
- It does not replace application-level auth; it only shrinks who can reach the listener.
- libvirt's own rule injection can surprise a strict host policy; verify after every libvirt upgrade.

## Recovery

- If a ruleset locks out needed traffic, the comments in workstation.nft document the load procedure: always `nft -c -f <file>` to check syntax first, keep the previous ruleset saved (`nft list ruleset >` backup), and apply with a timed revert available (e.g. apply in a `screen` session with a scheduled `nft flush ruleset` fallback, or use `nft --check` plus a console session).
- A broken firewall never survives a reboot if the ruleset is only applied manually; make persistence (systemd unit or network hook) a deliberate, tested step.

## Cost

Low ongoing cost. One-time cost: testing each desktop behavior (printing, casting, file sharing, VPN) against the drop policy and adding only what is actually needed.
