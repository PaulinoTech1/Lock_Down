# Egress Exclusivity Design

**Status:** design proposal for owner review. No host policy, guest XML, systemd unit, NetworkManager setting, USB binding, or kernel config is changed here.
**Branch/checkpoint reviewed:** `winddows-codex`, `b5818d414d7bffe1ab77b33662c2cd29d67886c4`; remote refs refreshed 30 September 2026.
**Related design:** [Two-Domain Workstation](TWO_DOMAIN_ARCHITECTURE.md).

## 1. Goal and threat boundary

Make this property an enforceable global safety invariant:

```text
NOT (HOST_EGRESS AND GUEST_EGRESS)
```

The only approved physical egress device is the external MediaTek MT7921U USB Wi-Fi adapter, VID:PID `0e8d:7961`. The built-in Intel Wi-Fi is outside the architecture. Ethernet, docking Ethernet, WWAN, other USB network devices, external bridges, and other physical paths are not approved. The work guest is assumed fully compromised. The host, its root account, kernel, KVM/QEMU implementation, and firmware are trusted; the design handles operator mistakes, automatic reconnect, guest/QEMU failures, restarts, reboot, re-enumeration, and interrupted handoff. It does not protect against malicious host root, a compromised kernel/hypervisor/firmware, physical attack, or a VM escape.

If ownership or state is uncertain, stop both sides from using egress. A stored state label never overrides live route, association, device, process, or firewall evidence.

## 2. Current repository evidence and unknowns

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| `config/candidate-6.18.53-lockdown-t14g3-audit11.config` | Baseline resolves `CONFIG_INET=y`, `IPV6=y`, `NETFILTER=y`, `NF_TABLES=y`, `BRIDGE=y`, `TUN=y`, `VIRTIO_NET=y`, `MT7921U=y`, all three required USB/IP symbols, and `VHOST_NET=y`. | Current Linux runtime, active modules/devices, egress, firewall, or final QEMU backend. |
| [Audit11 owner runbook](AUDIT11_OWNER_RUNBOOK.md) | KVM/TUN/vhost/IOMMU validation ran; one transient virtio-NIC guest obtained DHCP on its first launch; a later launch reported NIC down and no DHCP. | A working daily guest, MT7921U assignment, sustained guest networking, or host isolation. |
| [Current firewall sample](../nftables/workstation.nft) and [firewall guide](FIREWALL.md) | The sample uses `flush ruleset`, permits output by default, and describes libvirt NAT. | Live rules or a default-deny host egress boundary. |
| [Trusted guest profile](../vm-profiles/trusted-workstation/profile.md) | Its example has a libvirt NAT NIC. | That this XML is installed, or that its `vhost` comment matches the running QEMU command. |
| [Untrusted profile](../vm-profiles/untrusted-analysis/profile.md) | Despite its “isolated” label and prose, its XML defines `<forward mode='nat'/>`; it also uses virtio-net. | Isolation from the physical Internet. The prose and XML conflict and need reconciliation before use. |
| [Network lab profile](../vm-profiles/network-lab/profile.md) | Lab example networks use NAT and virtio-net; the profile says vhost is absent. | That its examples are live, that the guest backend is QEMU userspace, or that libvirt network autostart is off. |
| [USBGuard sample](../usbguard/rules.conf) and [USB guide](USB_SECURITY.md) | The MT7921U rule uses VID:PID and port path `4-1`; USBGuard controller/root-hub rules remain placeholders. | An enforcing, tested, serial-aware policy or current device authorization. |
| [Hardening sysctls](../sysctl/99-workstation-hardening.conf) | Existing sysctl sample has no IPv4/IPv6 forwarding-off invariant. | Live forwarding values. |
| [Audit12 stage-0 decision](audit12/STAGE0_REVIEW.md) | USB/IP core, VHCI, and HOST remain required; this is a capability/workflow decision. | That `usbipd` is active or exposed on the current host. |

The `winddows-codex` working tree was clean at the checkpoint. `git fetch origin --prune` first hit a Windows `.git/FETCH_HEAD` permission error and then succeeded with repository write permission; no remote ref changes were reported. The live Linux host, NetworkManager version/backend, libvirt/QEMU versions, Wi-Fi identity/topology, listeners, USBGuard mode, and current networking state are **UNKNOWN** from this Windows checkout. No serial number, SSID, secret, or private runtime evidence is included here.

## 3. Exact invariants

Let `H` mean the host is able to send Internet traffic through the approved MT7921U, `G` mean the work guest owns that adapter and can send Internet traffic through it, and `A` mean the adapter's egress ownership is proven from current device/driver/libvirt state.

1. `!(H && G)` holds in every state. `!H && !G` is the required safe-offline case, so exclusive OR is not the global invariant.
2. `SAFE_OFFLINE`, `TRANSITION`, and `ERROR` require `!H && !G`; there is no permitted default route for the host or Internet route for the guest.
3. `GUEST_EGRESS` requires `G && !H`: exactly one approved work guest, direct USB assignment of the one approved adapter, no host Wi-Fi association or external route, and a host egress/forwarding deny policy.
4. `HOST_MAINTENANCE` requires `H && !G`: all QEMU guests stopped, the adapter host-bound, and the maintenance egress lease explicitly active.
5. A missing, malformed, stale, contradictory, expired, or unreadable status record is `ERROR`; it never grants egress.
6. A route or association alone does not prove usable egress; nor does its absence prove isolation. The firewall and topology checks are required independently.
7. The daily guest has no virtual NIC, libvirt NAT network, external bridge, macvtap, TAP uplink, vhost-net egress, host DNS/DHCP, or automatic NAT fallback.
8. USB/IP kernel capability remains. USB/IP daemon/listener/export is disabled by default and is not an alternate physical egress path.
9. All transitions remove the current owner's egress first, establish `SAFE_OFFLINE`, verify, then enable the destination owner. No make-before-break transition is valid.
10. Unexpected network hardware, a second device claiming the approved identity, or uncertainty about physical path is `FAIL` or `UNKNOWN` and blocks an egress transition.

`G` is not just “USB hostdev appears in XML”: preflight must also verify that the host cannot use the device, the guest has no other network device, and owner-controlled validation has established Internet from the guest. `H` is not just “a route exists”: it includes an active association and an allowed host packet path. In non-maintenance modes the host firewall independently denies IP output and forwarding even if a crash rebinds the USB driver or stale state remains.

## 4. Required states

| State | Guest running | MT7921U owner | Host external route | Guest Internet | Host Internet |
| --- | ---: | --- | ---: | ---: | ---: |
| `SAFE_OFFLINE` | No | None/quarantined | No | No | No |
| `GUEST_EGRESS` | Yes, approved work guest only | Guest | No | Yes, direct USB Wi-Fi | No |
| `HOST_MAINTENANCE` | No QEMU guest | Host | Yes, via MT7921U only | No | Yes, time-limited |
| `TRANSITION` | No | None/quarantined | No | No | No |
| `ERROR` | No | None/quarantined or unknown, firewall deny enforced | No permitted route | No | No |

Any other combination is invalid. A networkless work guest may be permitted later in `SAFE_OFFLINE` for local maintenance only after its XML is separately proven to have no NIC and no attached MT7921U; the simple initial implementation should stop the guest instead.

```text
                         explicit verified start
       +---------------- SAFE_OFFLINE ----------------+
       |                                              |
       v                                              v
  GUEST_EGRESS                                    HOST_MAINTENANCE
  guest owns MT7921U                              host owns MT7921U
       |                                              |
       +-----------+                          +-------+
                   v                          v
                    SAFE_OFFLINE (all egress denied)
                              |
                 invalid/ambiguous/failure
                              v
                            ERROR
                  deny egress; local recovery only

Every ownership change passes through SAFE_OFFLINE.
TRANSITION is the locked, egress-denied interval between states.
```

Only `SAFE_OFFLINE -> GUEST_EGRESS` and `SAFE_OFFLINE -> HOST_MAINTENANCE` may grant egress. Every exit goes first to `TRANSITION` with egress disabled; failed checks go to `ERROR`. `ERROR -> SAFE_OFFLINE` requires an explicit local recovery action that reasserts the deny rules, stops guests, disconnects host Wi-Fi, removes routes/DNS, quarantines the adapter, and verifies the offline predicates. If any required check remains `UNKNOWN`, remain in `ERROR`.

## 5. Enforcement layers

Use independent controls so a libvirt USB release does not become host Internet access:

1. **Ownership:** the MT7921U is either detached for the approved QEMU USB hostdev, host-bound for maintenance, or offline/quarantined. Use current sysfs and libvirt evidence for the physical path, VID:PID, interface driver and assigned domain. A USB bus number can change; do not identify a device by VID:PID alone. Keep private serials out of repository output.
2. **Host egress guard:** an always-loaded nftables policy drops all non-loopback host output and all IP forwarding in offline, transition, guest, and error modes. A separate explicit maintenance authorization may allow host output only over the verified MT7921U interface. Inbound remains default-deny; only maintenance return traffic and separately approved local-only services are considered. IPv4 and IPv6 are handled together.
3. **Topology and sysctls:** no physical bridge, route, NAT, masquerade, forwarding, TAP uplink, or network namespace with an external device is permitted in daily guest mode. Verify both IPv4 and IPv6 forwarding settings and every interface/namespace. Their desired kernel/runtime values are not established by this checkout.
4. **Network manager:** Wi-Fi autoconnect is disabled persistently. Outside maintenance, the adapter is disconnected and unmanaged/quarantined by the actual installed manager. Maintenance activates the approved profile explicitly. A NetworkManager device-state toggle alone is not durable across service restarts; use persistent autoconnect controls and verify behavior on the installed version. If the host uses iwd, systemd-networkd, wpa_supplicant directly, or another manager, design for the observed stack instead.
5. **Guest gate:** no work guest autostart, default libvirt network autostart, or user-facing direct start path. A privileged, root-owned `lockdown-net` controller is the only ordinary start/transition interface. Restrict libvirt lifecycle authorization to that interface where practical.
6. **Verification:** rederive state from the kernel, routes, NetworkManager, sockets, firewall, libvirt XML/live process, USB tree, and guest-side connectivity; never trust a state file or a configuration example by itself.

The firewall is the runtime backstop if the adapter returns to the host. NetworkManager unmanaged state, no-autoconnect profiles, route/DNS teardown, USBGuard, and libvirt gating reduce the chance of that state; none replaces the firewall deny. The host is trusted, so a malicious root user who deletes every control is outside scope. The operator-error case of an ordinary service reload or guest crash is in scope and must be exercised.

## 6. Host firewall design

Create a dedicated egress guard as part of a single reviewed nftables ownership plan:

| Hook / path | `SAFE_OFFLINE`, `GUEST_EGRESS`, `TRANSITION`, `ERROR` | `HOST_MAINTENANCE` |
| --- | --- | --- |
| Host `inet output` | Allow loopback only; drop every other packet, including established traffic and packets with a stale route. | Allow only via the verified MT7921U interface while a short-lived maintenance lease exists. No other interface. |
| Host `inet input` | Drop external traffic; no listening service exception by default. | Drop new inbound sessions; accept only required return traffic and minimal DHCP/IPv6 control from the MT7921U. |
| `inet forward` | Drop all forwarded packets. | Drop all forwarded packets. |
| `bridge output` and `bridge forward` | Drop bridge-originated and bridged frames; work guest may not be attached to a bridge. | Drop bridge-originated and bridged frames; no VM or host traffic is forwarded. |
| NAT/masquerade | No work-guest rule or active libvirt NAT path. | No guest NAT; host is the only domain using the radio. |

Exact maintenance ports are intentionally not fixed here: repository mirrors and time services vary. The initial maintenance exception is bound to the one verified egress interface, host-only and guest-stopped predicates, and a short expiring lease; the owner should decide the time limit before implementation. Narrow endpoint/port rules can be evaluated after observing actual update requirements. The lease must be renewed explicitly and must not survive reboot. When it expires, host egress drops even if routes or association remain; a watchdog then tears down the association, routes, DNS and authorization. A stale route never opens the firewall.

Use separate `inet output`/`forward` and `bridge output`/`forward` guard hooks with terminal drop verdicts that cannot be undone by another chain's `accept`; validate hook support and priority against the installed nftables/libvirt/firewalld backend. Do not rely on a default policy in a regular, unattached chain. Use one atomic transaction to change the guard state. Do not run `nft flush ruleset` during a handoff. The current [workstation sample](../nftables/workstation.nft) starts with a global flush and output `accept`; it cannot be applied unchanged alongside this guard. Libvirt, firewalld, NetworkManager shared-mode, and legacy iptables-nft rules must not be allowed to remove or bypass the guard. Enumerate the complete live ruleset after each permitted daemon start/reload.

The guard must load before any interface manager or libvirt service/socket can activate. Make the actual manager and libvirt start depend on successful guard installation and order after it; simple `Before=network.target` is not sufficient proof because `network.target` is passive. On a guard-load failure, block network-manager/libvirt activation rather than launching them without policy. Keep a local-console recovery path. The guard stays installed when the controller process exits; no state change may temporarily remove it.

Disable IPv4 and IPv6 forwarding persistently for the normal host and verify per-interface settings. Drop forwarding at nftables too. Inspect IPv4 and IPv6 routes and policy rules, bridge links, TAP devices, active NAT, all network namespaces and their uplinks, and DNS route/connection state. A missing default route does not prove isolation. Since USB direct assignment does not pass guest IP packets through the host network stack, host IP forwarding is not needed to provide guest Internet.

## 7. USB ownership and device identity

The physical adapter is used in two mutually exclusive roles:

| State | Host USB/network view | QEMU/guest view |
| --- | --- | --- |
| Offline | Absent or host-enumerated but disconnected, unmanaged and quarantined; no host IP egress. | Not assigned. |
| Guest | USB device detached from the host network driver and opened by the approved QEMU domain. Host has no corresponding Wi-Fi netdev/association. | Guest loads the MT7921U driver/firmware and obtains Wi-Fi directly. |
| Maintenance | Host USB and `mt7921u` driver own it; connection profile activation is manual after the firewall lease. | No QEMU process or guest attachment. |

Libvirt's domain XML documentation states USB host devices are detached on guest startup and reattached after guest exit or hot-unplug. That confirms the crash-relevant mechanism; it does **not** prove which kernel driver rebinds or whether NetworkManager associates on this machine. Therefore, do not assume the adapter stays guest-owned after QEMU exits. Keep host output denied in `GUEST_EGRESS` and `ERROR`; persistently disable autoconnect; test guest process crash, libvirt restart, USB unplug/replug, and host reboot with the live host owner.

The current USBGuard file identifies `0e8d:7961` on `4-1`, while controller and hub rules are placeholders and the serial is private/unfilled. Keep the MT7921U host driver compiled for maintenance. USBGuard policy should deny unknown network-capable USB devices after a proven inventory, preserve trusted keyboard/recovery devices, and permit MT7921U only on the approved physical path. Device descriptors and port path are not cryptographic identity. Do not change the live USBGuard policy from this Windows design pass.

The built-in Intel Wi-Fi is not an alternate maintenance route. It must not associate, acquire a host route, or be exposed to the guest. Do not assume it is absent: its physical inventory and driver binding are `UNKNOWN`; detection of it as an active egress interface is a failure. No onboard or docking Ethernet is a permitted route in either networked state. During maintenance only the MT7921U may supply host egress.

## 8. Network services and unexpected NICs

| Service/device | Normal `SAFE_OFFLINE` / `GUEST_EGRESS` | `HOST_MAINTENANCE` | Evidence still needed |
| --- | --- | --- | --- |
| NetworkManager or actual Wi-Fi manager | Adapter disconnected, no saved profile auto-connect, unmanaged/quarantined; no global route or external DNS. | Explicitly authorize and activate one profile; autoconnect remains off. | Identify actual manager/version; profile, autoconnect, device state and DNS behavior. |
| `wpa_supplicant` / iwd | No host association path for the adapter. | Used only if required by the actual manager. | Process, D-Bus and unit ownership; backend. |
| `systemd-resolved` | No external DNS link/server/route. Local stub may exist only if it has no upstream. | DNS only on the MT7921U link while the lease is live. | `resolvectl`, NM/device state, listening sockets. |
| `dnsmasq` / libvirt networks | No NAT/default guest network; no guest-reachable host DNS/DHCP. | No guest or libvirt network required. | Active networks, autostart, process argv and sockets. |
| avahi, mDNS, LLMNR, CUPS discovery, SSH | Disable or keep local-only if not required; never expose on an external address in normal mode. | No new inbound listener; temporary client use only if approved. | Listening sockets, service activation, desktop dependencies. |
| libvirt, SPICE, VNC | Local Unix sockets only; no TCP management or display listener; work guest has no NIC. | Guest stopped; no remote API/listener. | Modular daemon/socket set and live listeners. |
| USB/Ethernet/PCI/WWAN network devices | Any unapproved netdev, USB NIC or external bridge fails preflight. | Still disallowed; maintenance path remains MT7921U only. | PCI/USB/netdev inventory and driver identity. |

If another network-capable device appears, report `FAIL` or `UNKNOWN`, do not choose one automatically, and remain offline. A host firewall that drops output is a useful backstop, not permission to leave an unexpected NIC authorized. Unknown USB NICs must be blocked by USB policy once USBGuard has a tested allowlist. Do not disable packages or drivers until the local hardware and recovery implications are reviewed.

## 9. Libvirt, QEMU, and guest start/stop behavior

**Daily work guest XML target:** no `<interface>` element, no network source, no guest DHCP/DNS, no TAP/bridge/macvtap, no virtio-net and no fallback network device. Include a single device-specific USB hostdev for the approved adapter, with local display only and the minimal devices approved in the two-domain architecture. Reject XML that has any alternate NIC, USB redirection, or unapproved host device.

**Autostart:** work guest autostart off. Libvirt `default` and every NAT/route network used by historical profiles must not autostart into the daily mode. The work guest must not be started by virt-manager, `virsh`, a desktop autostart, a libvirt socket activation path, or a transient script outside the egress controller. Restrict ordinary lifecycle authorization to the local controller; root remains trusted and can override policy, which is a residual risk.

**Start gate:** the privileged `lockdown-net guest` operation acquires the transition lock, enters `TRANSITION` with host egress denied, stops any guest/domain with a conflicting device claim, verifies no QEMU process remains for that device, verifies all host route/DNS/association/forward/NAT checks, verifies the exact device path and approved guest XML, and verifies IOMMU/AppArmor preconditions. It then requests libvirt start, verifies live XML/process ownership and that no host Wi-Fi interface/route/association appeared, and records `GUEST_EGRESS` only after verification. If any step fails, stop the domain, keep host egress denied, perform best-effort offline cleanup, report `ERROR`, return nonzero, and require local recovery. There is no NAT fallback.

Use libvirt's QEMU `prepare` or `start` hook as a start veto only if the installed release supports the required behavior. Libvirt documents that nonzero status at pre-start hook locations aborts VM start and warns hooks not to call back into libvirt because the daemon is waiting and may deadlock. Thus, a hook must be short, bounded, non-networked, and must not invoke `virsh`; it can validate a root-owned, single-use start authorization from `/run` and fail closed. Avoid having it reacquire a lock already held by the launcher. Keep the hook version-specific and test direct GUI/CLI bypass. The controller, not a stop hook, owns cleanup.

**Maintenance gate:** acquire the same lock; first deny egress and stop the work guest and every other QEMU guest; wait for QEMU exit; confirm libvirt has released the MT7921U; clear external routes/DNS/association; enter and verify `SAFE_OFFLINE`; then bind/authorize the adapter to the host and explicitly enable the manager/profile. Only after interface identity, firewall lease, route, DNS, and no-guest checks pass may the state become `HOST_MAINTENANCE`. If any check fails, tear down host networking, leave egress denied and report `ERROR`.

**Maintenance exit:** under the same lock, remove the firewall maintenance lease first. Disconnect the host profile, stop/disable manager control of the device, remove external IPv4/IPv6 routes and DNS, release the device to offline/quarantined state, stop relevant network sessions, verify no host external path, then report `SAFE_OFFLINE`. Guest start remains locked out until all checks pass. If the host's version cannot reliably quarantine the interface across manager/service restart, do not enable guest start until the design is revised.

## 10. Failure and reboot behavior

| Event | Required immediate state | Mechanism and next action |
| --- | --- | --- |
| QEMU exits normally or crashes | Host egress still denied; no automatic transition to maintenance. | libvirt may reattach USB; autoconnect is off, host manager is quarantined, and nft guard drops host output. Post-stop cleanup returns to `SAFE_OFFLINE`; if cleanup cannot verify, `ERROR`. |
| libvirt restarts or its socket activates | No guest autostart; host egress denied. | Work guest/network autostart off; start gate is mandatory. Inspect daemon/network state after restart. |
| Controller crashes during a transition | No host egress; guest remains stopped or is stopped by watchdog. | Offline nft policy was applied first and remains in kernel. Short maintenance lease expires to deny. A systemd watchdog performs cleanup; absent proof, require local recovery. |
| Maintenance timer/lease expires | `ERROR` or `SAFE_OFFLINE`, never online maintenance. | nft kernel timeout drops host output even if the manager retains a route; cleanup service disconnects and removes routes/DNS. Guest start remains blocked until observed state is clean. |
| Host reboot/power loss | Boot default is `SAFE_OFFLINE`; no persistent maintenance lease. | `/run` state vanishes; nftables loads offline guard before managers/libvirt; manager autoconnect disabled; guests and networks autostart off. Failed guard load prevents network/libvirt activation. |
| Adapter unplug/re-enumeration | `ERROR`, host egress denied; no attempt to select another NIC. | Device event notifies the controller via a simple systemd service, not a long-running udev script. Require exact approved path, fresh owner verification, and explicit new transition. |
| Unexpected NIC, active NAT, route, listener or XML change | `FAIL`; do not start guest or maintenance. | Read-only verifier reports evidence; controller remains in/returns to offline. Human review and local repair required. |
| Ambiguous state, partial operation, stale state file | `ERROR`; no owner enabled. | Observed kernel/device/service state overrides file; force deny, stop guests, disconnect adapter and verify locally. |

The firewall guarantee is that the host cannot send IP packets through an unapproved or accidentally rebound NIC in non-maintenance states. If systemd cleanup itself fails after a maintenance lease expires, association/routes may remain until local recovery, but nftables still denies host egress and the state is `ERROR`; no guest start is allowed. The assurance depends on protecting the firewall rules from unrelated ruleset flush/replacement. A verified boot-loaded firewall dependency and least privilege for firewall writers are therefore part of the gate, not optional cleanup.

## 11. Serialized controller and state storage

Provide a small root-owned command surface:

```text
lockdown-net status [--expect offline|guest|maintenance]
lockdown-net offline
lockdown-net guest
lockdown-net maintenance
```

`status` is read-only. Every mutating command prints the requested transition, obtains `flock` on one root-owned lock under `/run/lockdown-net/`, verifies current reality, applies the offline deny first, performs a single transition, verifies the result, logs a sanitized result, returns nonzero on any failure, and always releases the lock. `flock` serializes competing start/maintenance/USB ownership requests and releases automatically if the process dies; a PID file alone is insufficient.

State/authorization records live only under root-owned `/run/lockdown-net/`, have restrictive permissions, bounded schema/version and short expiry. Reboot forgets maintenance authorization. State is an audit hint and a one-shot launch capability, never truth. A state file claiming `GUEST_EGRESS` while the host owns or is associated to Wi-Fi is an error. If the controller dies, the firewall lease expires to deny; a recovery service can attempt cleanup, but unknown evidence remains `ERROR`.

Systemd targets may express boot ordering and named states, but a target is not a mutual-exclusion primitive and `After=` by itself does not require another unit to succeed. Prefer a single state controller with systemd dependencies that make the firewall a required prerequisite for the actual network manager and libvirt daemon/socket activation. Evaluate a one-shot guard service plus a controller over separate long-running per-state targets to avoid target cycles and recursive stop/start races. Exact units depend on observed Ubuntu/libvirt/network manager versions. Keep autostart disabled; no dependency on desktop login.

## 12. USB/IP and NAT interaction

Keep `CONFIG_USBIP_CORE=y`, `CONFIG_USBIP_VHCI_HCD=y`, and `CONFIG_USBIP_HOST=y`. Compiled support is not a daemon, route, or listener. Default policy in every state: `usbipd` not active, no external listener, no automatic import/export. A distinct owner-approved USB/IP workflow may require a host-only static link and a narrow, guest-specific listener; it must not add a default route, NAT, or physical uplink to the host. Its exact direction/peer/device workflow is currently unknown, so it is not authorized by this design. If the existing workflow requires a remote network peer, run it only in an explicit approved state whose physical egress owner is singular, with host firewall and endpoint scoped; do not silently run it during ordinary work.

Direct USB assignment is preferred for the local MT7921U because it removes host NAT/TAP/DNS/DHCP from the Internet path. USB/IP adds a host USB/IP parser, TCP endpoint and IP transport and gives the guest an additional host-reachable service; it offers no demonstrated advantage for this local radio. Do not force USB/IP for Wi-Fi just because its kernel support is required.

Work guest NAT, default libvirt network, and host forwarding are prohibited in `GUEST_EGRESS`. If direct assignment fails, the guest has no Internet until an owner-approved architecture revision. Historical `untrusted-analysis` and `network-lab` docs are retained for reference, but their current NAT examples cannot run concurrently with the exclusive-egress daily state. Separate isolated/no-forward lab workflows require their own approved state and must not gain Internet accidentally. Audit `virbr0`, all libvirt network XML/autostart, `dnsmasq`, TAP, bridges, `MASQUERADE`, NAT chains, QEMU NICs, and host/guest routes.

## 13. Unexpected device and path policy

Before granting host or guest egress, enumerate physical PCI and USB network devices, USB interfaces and drivers, sysfs device path, netdevs, bridge ports, active routes, and every process/network namespace with an external interface. Compare to one locally configured, owner-approved MT7921U path. Runtime IDs (serial, SSID, BSSID, MAC, IP, device descriptor names) must be redacted from committed logs and generic fixtures. The currently documented USB port path is useful evidence but not immutable identity.

`FAIL`: a second connected NIC, any unapproved USB NIC, any Ethernet/WWAN/default route, guest virtio NIC, active external bridge, work-guest NAT, usbipd external listener, unexpected manager association, or duplicate match for the approved device. `UNKNOWN`: inventory command failed, identity is ambiguous, service state is unreadable, or dynamic interface cannot be bound to the expected USB path. Both statuses deny transitions.

## 14. Read-only verifier design

The future `scripts/verify-control-domain-isolation.sh` (or equivalent) supports:

```text
--expect offline
--expect guest
--expect maintenance
```

It must not change links, services, rules, routes, device bindings, libvirt state or profiles. For each check it prints one of `PASS`, `FAIL`, `WARN`, `UNKNOWN`, `NOT_APPLICABLE`, plus a reason and redacted evidence. Provide human-readable output and JSON. Exit semantics:

| Exit | Meaning |
| ---: | --- |
| 0 | Every safety-critical predicate for the requested state is `PASS`; required mode-specific manual evidence has been supplied and is fresh. |
| 1 | A safety-critical predicate is `FAIL`. |
| 2 | Any required predicate is `UNKNOWN`/`WARN`, or manual validation is outstanding; caller must not treat the state as approved. |
| 3 | Bad arguments or verifier/runtime error. |

For **offline**, check no QEMU work guest/MT7921U assignment, no host association, external routes or DNS, output/forward/bridge egress denied, no forwarding/NAT/default network, no unexpected NIC, USB/IP external listener absent, and guard loaded.

For **guest**, check exactly the approved domain is running; its inactive and live XML contain only the allowed MT7921U hostdev and no virtio NIC/network source; correct physical adapter is assigned and not host-driver-bound; host has no Wi-Fi association, external IPv4/IPv6 route/policy route, DNS egress, forwarding, NAT or bridge path; no unexpected egress interface; external usbipd, remote libvirt, SPICE/VNC TCP listeners absent; AppArmor/sVirt enforcing, QEMU unprivileged, KSM off, IOMMU evidenced and CPU nested-virtualization policy recorded. Guest Internet requires separate guest-side/manual evidence; do not infer it from XML.

For **maintenance**, check all QEMU guests stopped; QEMU does not hold the MT7921U; the exact adapter is host-bound; the maintenance lease is live; only that interface has a host external route/DNS; no work-guest Internet path, external listener, USB/IP external listener, bridge forwarding or unexpected NIC; and no stale/contradictory state. Host updates can proceed only when required checks are `PASS`.

Read IPv4 and IPv6 route and rule tables, all addresses including global scope, resolver/per-link DNS and routing domains, manager state and autoconnect, nft rules and hooks, sysctls, bridge/TAP/veth state, libvirt networks/domains/autostart, QEMU command lines/UID/capabilities/LSM/seccomp, USB driver/path/hostdev state, listening sockets and namespaces. A command failure is `UNKNOWN`, never interpreted as absence. No fixture-generated host data is `PASS` for the real ThinkPad.

The existing [evidence collector](../scripts/collect-validation-evidence.py) currently collects useful bounded kernel/hardware evidence but has no egress state machine checks and reports `kvm-network-prerequisites` as WARN when vhost-net or TUN is unavailable. It should be extended only after design approval; its JSON must continue to mark observations separately from physical/manual tests and must never include USB serials, SSIDs or secrets.

## 15. Test matrix

Repository fixture tests belong to the later, approved implementation stage. Every fixture is synthetic and must avoid host identifiers. Each unsafe case must return nonzero with a `FAIL` or `UNKNOWN` result; absence of evidence is never success.

| Case | Expected result |
| --- | --- |
| SAFE_OFFLINE baseline; guard drop present; no links/routes | PASS offline |
| Guest and host both claim same adapter | FAIL; neither egress grant accepted |
| IPv4 default route present in guest mode | FAIL |
| IPv6 default route or IPv6 policy rule present in guest mode | FAIL |
| Non-default external route present | FAIL |
| Host associated to Wi-Fi with no default route | FAIL |
| External DNS server or per-link DNS route remains | FAIL |
| Forwarding enabled in IPv4 or IPv6 | FAIL |
| NAT/masquerade or active default libvirt network remains | FAIL |
| External bridge, TAP uplink, or network namespace has external route | FAIL/UNKNOWN |
| Unexpected USB/PCI/Ethernet/WWAN network device | FAIL/UNKNOWN |
| `usbipd` listening on `0.0.0.0` or `::` | FAIL |
| Work guest XML includes virtio NIC or default libvirt network | FAIL |
| Work guest autostart enabled or unauthorized start request | FAIL/start veto |
| QEMU exits and libvirt reattaches USB; host NM profile would autoconnect | FAIL; firewall still denies; state ERROR |
| NetworkManager restart or device re-enumeration occurs outside maintenance | FAIL/ERROR; no egress |
| Maintenance authorization record survives simulated reboot | FAIL; boot must be offline |
| Transition lock already held | Second mutator fails/busy; no state change |
| State record disagrees with observed route/device/firewall | FAIL; observed reality wins |
| Firewall guard missing, replaced, or load command fails | FAIL; network manager/libvirt must not activate |
| Guest Internet test succeeds while host route/association is absent and direct assignment verified | PASS guest after independent manual/external test |
| Correct host maintenance only on MT7921U, all guests stopped and timed lease active | PASS maintenance |
| Error during each transition step | Egress remains denied; operation exits nonzero; recovery required |

Live owner validation after an approved implementation must additionally test: host cannot reach external IPv4/IPv6 from guest mode; guest Internet works only through its assigned MT7921U; guest cannot reach host SSH/DNS/libvirt/desktop services; suspend/resume; unplug/replug; QEMU crash; libvirt restart; maintenance interruption; power loss; and real boot back to `SAFE_OFFLINE`. Never flush the production firewall as a test. Use an isolated lab or disposable image and local console.

## 16. Kernel hardening candidates and current disposition

Kernel configuration does not implement the ownership state machine. Preserve required protocol/device support while the system-level controls are reviewed. The candidate set is deliberately limited to one plausible cut; no config change is proposed now.

| Symbol(s) | Current effective value | Candidate / disposition | Why and what exposure changes | Dependencies/collateral, workflow impact and required evidence |
| --- | --- | --- | --- | --- |
| `CONFIG_VHOST_NET` | `y` | **Only plausible future single-symbol cut:** consider `n` after approved profiles and live QEMU argv confirm no retained guest needs host-kernel vhost acceleration. No cut now. | Removes the host-kernel virtio-net vhost backend interface and therefore the vhost descriptor path for guests. It does not remove virtio-net/QEMU networking, host Internet, NAT, or guest networking by itself. | Linux v6.18.53 `drivers/vhost/Kconfig` defines `VHOST_NET` as depending on `NET`, `EVENTFD`, and TUN/TAP compatibility expressions, and selecting `VHOST`. The same baseline keeps `VHOST_SCSI=y` and `VHOST_VDPA=y`, which also select the shared VHOST core; a VHOST_NET cut therefore is not expected to remove that core, but the full resolved config diff must prove it. `scripts/kvm-smoke.sh` uses `-nic none`, so its guest boot does not need vhost-net. USB/IP and host Wi-Fi maintenance do not inherently need it. But audit11 `virt-host-validate` explicitly checked it; `collect-validation-evidence.py` reports it as a KVM network prerequisite; historic profiles all include virtio-net and their “no vhost” comments are not live evidence. Capture QEMU argv/libvirt XML for each retained profile, explicitly select QEMU userspace backend where supported, update tests/report semantics, benchmark network workflows, resolve the exact v6.18.53 Kconfig, review full `olddefconfig` delta, then owner-review one-symbol candidate. |
| `CONFIG_TUN`, `CONFIG_BRIDGE`, `CONFIG_VIRTIO_NET` | `y` | Retain. | TUN/TAP, Linux bridge, and virtio-net underpin existing libvirt NAT/lab and historic virtual NIC workflows. Work guest will not use them in the target, but other profiles and test cases remain. | TUN is checked by `virt-host-validate` and real libvirt networking; `scripts/kvm-smoke.sh` alone does not need it. Network-lab uses multiple bridged libvirt networks. Retire/rewrite every workflow and prove USB/IP transport before proposing cuts. |
| `CONFIG_INET`, `CONFIG_IPV6`, `CONFIG_NETFILTER`, `CONFIG_NF_TABLES` | `y` | Retain. | Needed for host maintenance networking and the dual-stack egress enforcement/verification path. | IPv4/IPv6 must remain available to host maintenance; nftables is the intended firewall. Turning protocol support off cannot replace runtime policy. |
| `CONFIG_MT7921U` and wireless stack | `y` | Retain. | The host needs this driver for explicitly authorized maintenance mode; guest assignment is runtime device ownership. | Do not remove or disable the host driver. USB device/driver binding and guest firmware need live ThinkPad validation. |
| `CONFIG_USBIP_CORE`, `CONFIG_USBIP_VHCI_HCD`, `CONFIG_USBIP_HOST` | `y` | Preserve by owner decision. | Required import/export workflows. | No Kconfig removal question; daemon exposure is handled at runtime. |
| Other USB/PCI network drivers, tunnels, packet sockets, netfilter helpers, namespaces, MACVLAN/MACVTAP, VSOCK/VHOST_VSOCK | Config values/workflow consumers require targeted inventory. `MACVLAN` and `MACVTAP` are `y`. | Unknown; no candidate. | The target design does not use them for work-guest Internet, but host maintenance, containers, desktop/VPN, USB/IP or lab recovery may. | Enumerate exact resolved symbols, userspace opens, libvirt/desktop profiles, dependencies and recovery impact. Do not bulk-disable families or confuse compiled capability with active exposure. |

**Current recommendation:** no audit12 kernel cut at this egress-design checkpoint. `VHOST_NET=n` is a focused future candidate, not a conclusion that no workflow needs it. The remaining current libvirt XML/profile and validation contracts must be reconciled first. Keep audit11 and stock fallback paths. Any kernel proposal requires authenticated exact-source review, full resolved config collateral diff, tests, and a separate owner gate.

## 17. Network namespace decision

Do not add a maintenance network namespace in the first design. The daily-mode protection is achieved by direct USB device assignment, an always-loaded host output/forward deny, no host association or route, and no guest network backend. Maintenance already stops all guests and explicitly uses the trusted host for updates. Moving NetworkManager, DNS, apt, firmware tools and time sync into a namespace would add link handoff, DNS, routing, service-manager and recovery complexity without improving the required host/guest exclusivity invariant. Revisit only if maintenance browsing or a second untrusted host workload becomes a supported use case and can be isolated with a measured benefit.

## 18. Operator experience and recovery

The four-command surface in section 11 keeps ordinary operation understandable. `status` should state the observed state, the failed/unknown predicates, adapter owner (redacted identity), current route/association truth, active firewall mode/lease expiry, guest process/XML result, and the one safe next action. Mutating commands show the intended transition, refuse unsupported paths, serialize through one lock, apply deny-first ordering, verify at the end, log a redacted result, and return nonzero for incomplete work. Do not require memorizing shell fragments or expose hidden NAT fallback.

Keep a local console available. Before implementation, retain and verify signed audit11/stock boot choices, host recovery access, current firewall/NM/libvirt/USBGuard backups, and the guest disk. No USB network handoff, GRUB change, new nftables rule, NetworkManager edit, systemd unit, libvirt XML change or USBGuard rule is applied by this design document. If online update mode is interrupted, the lease denies output; the owner returns to offline manually and verifies before guest start. If device identity or recovery path is unclear, leave it unplugged/offline and use the existing physical recovery path.

## 19. Performance and residual risks

Steady-state policy checks add a small packet-filtering path for host-local IP packets; no claim is made about measured cost. The work guest's Internet path becomes USB device -> QEMU USB hostdev -> guest MT7921U driver -> guest network stack, with no host NAT, DNS/DHCP forwarding, TAP, bridge or vhost-net for Internet. Measure Wi-Fi throughput/latency, guest CPU/wakeups, idle/active power, resume stability, adapter handoff time, maintenance entry/exit time, and compare with the old NAT profile on identical conditions. A network throughput or battery claim requires actual ThinkPad measurements.

Residuals: USB descriptors and port identity can be spoofed or change; host USB core and QEMU USB emulation still process the device; the host can still inspect a running guest; KVM/QEMU/kernel/device firmware escapes remain; trusted root can undo controls; NetworkManager or libvirt versions can change behavior; UI/operator mistakes can leave routes or listeners; maintenance mode deliberately grants the host Internet for updates. The host firewall and gate reduce accidental concurrent egress but do not make a compromised host trustworthy.

## 20. Approval-gated implementation sequence

The following stages are reversible and require approval before the listed repository artifacts are built or any live policy is touched:

1. **Read-only verifier and inventory:** add CLI modes and JSON/human report from live checks; no mutation. Build synthetic fixtures for every unsafe state; seed each gate red and prove it fails.
2. **Guest XML validator and offline policy templates:** validate approved work guest has no NIC/NAT and contains only assigned Wi-Fi device; author test-only nftables guard templates and review dual-stack/bridge hook ordering.
3. **State controller and systemd design:** serialize transitions, root-only `/run` state, expiring maintenance lease, network-manager/libvirt boot dependency and failure behavior; no ThinkPad deployment.
4. **Network-manager and USBGuard policy proposal:** exact version-specific unmanaged/autoconnect and allowlist plan; simulate service restart/re-enumeration with fixtures; never commit serials.
5. **QEMU/libvirt gate:** autostart off, pre-start hook veto and polkit path tested in disposable XML; explicit no-NIC/no-NAT and correct USB identity.
6. **Kernel review:** only after retained guest workflows and tests agree, prepare at most one `VHOST_NET` cut proposal. Do not edit audit11 effective config or make audit12 candidate without owner review.
7. **Owner-supervised ThinkPad validation:** local console, verified backup/fallback, separate owner authorization for loading rules, changing services, binding the live adapter and physical handoff; perform one transition at a time and restore SAFE_OFFLINE after each.

**Stop point:** deliver this design for owner review. Repository implementation artifacts, kernel config changes, and all live ThinkPad actions remain gated by the attachment's explicit owner approval requirements.

## 21. Upstream references

- [libvirt domain XML: USB hostdev detach/reattach and guest networking](https://libvirt.org/formatdomain.html)
- [libvirt QEMU hooks: pre-start veto, stop/release events, no callbacks into libvirt](https://libvirt.org/hooks.html)
- [libvirt network XML: isolated/NAT forwarding, host DNS/DHCP behavior](https://libvirt.org/formatnetwork.html)
- [NetworkManager connection autoconnect setting](https://networkmanager.dev/docs/api/latest/settings-connection.html)
- [NetworkManager unmanaged device configuration and version-specific behavior](https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html)
- [nftables manual: base-chain priorities, verdicts, ruleset operations](https://netfilter.org/projects/nftables/manpage.html)
- [Linux TUN/TAP documentation](https://docs.kernel.org/networking/tuntap.html)
- [Linux USB/IP protocol](https://docs.kernel.org/usb/usbip_protocol.html)
- [Linux v6.18.53 VHOST Kconfig](https://github.com/gregkh/linux/blob/v6.18.53/drivers/vhost/Kconfig)
- [QEMU security guidance](https://www.qemu.org/docs/master/system/security.html)
- [systemd network target semantics](https://systemd.io/NETWORK_ONLINE/)
