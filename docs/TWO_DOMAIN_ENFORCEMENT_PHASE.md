# Two-domain enforcement phase

**Status:** design written for owner review on 30 September 2026. The subsequent owner instruction authorized repository implementation on a separate branch. Live ThinkPad policy changes still require the separate gates below. The design branch is `windows-codex`; its implementation starting checkpoint was `2a48734`.

This phase makes the [two-domain architecture](TWO_DOMAIN_ARCHITECTURE.md) and [egress exclusivity design](EGRESS_EXCLUSIVITY_DESIGN.md) mechanically checkable. The work guest is assumed fully compromised. Only the approved MT7921U USB Wi-Fi device (`0e8d:7961`) may provide physical egress, under exactly one owner. The control host and its root account remain trusted. This is Qubes-inspired compartmentalization, not Qubes-equivalent isolation.

## 1. Corrected formal invariants

Let `H` mean the host can send external traffic through the approved adapter and `G` mean the work guest can do so. The global safety condition is `!(H && G)`. The former `H XOR G` statement was wrong because `SAFE_OFFLINE` legitimately has `H=0, G=0`; the [egress design](EGRESS_EXCLUSIVITY_DESIGN.md) is corrected accordingly. A state name or saved token is never proof of `H` or `G`.

| State | H | G | Required ownership and gate |
| --- | ---: | ---: | --- |
| `SAFE_OFFLINE` | 0 | 0 | Egress guard active; no guest or host external path |
| `GUEST_EGRESS` | 0 | 1 | One approved guest owns the adapter; host guard remains closed |
| `HOST_MAINTENANCE` | 1 | 0 | No QEMU guest; verified host adapter and expiring authorization |
| `TRANSITION` / `ERROR` | 0 | 0 | Deny rules remain; uncertain evidence blocks a grant |
| Forbidden | 1 | 1 | Immediate failure and deny-first recovery |

`G=1` cannot be established by repository XML alone: actual guest Internet needs owner-observed or later trusted guest evidence. The repository can prove only that a proposed configuration lacks alternate guest network paths and that synthetic state evaluation rejects contradictory observations. A command failure, inaccessible namespace, ambiguous device, or missing data is `UNKNOWN`, never an empty successful inventory.

When leaving guest mode, the guest may still have egress while it shuts down; the host guard must remain closed and the observed state remains `GUEST_EGRESS` until the guest releases the adapter. Only then may the controller record `TRANSITION` or `SAFE_OFFLINE`. When leaving maintenance, close the host guard first, verify `H=0`, then enter `TRANSITION`. Never label an in-flight state as both offline and online or open the destination before the source is proven closed.

## 2. Authoritative production VM profile

After this spec is approved, create exactly one production profile under `vm-profiles/work-domain/`, with structured libvirt XML and a validator. It represents the `qemu:///system` work guest. Its normal mode permits a single physically verified MT7921U USB hostdev, local display/input, one bounded guest storage volume, and minimal required virtual devices. No other profile is a daily work-domain recipe.

The validator must parse XML and reject every `<interface>` (including network, bridge, direct/macvtap, user, or passthrough forms), `<filesystem>` (9p/virtiofs), `<channel>`/`<serial>` that exposes a guest agent or clipboard path, `<redirdev>`, unauthorized USB or any PCI `<hostdev>`, remote graphics listeners/WebSockets, and raw QEMU command-line overrides. It must check explicit SPICE `<clipboard copypaste='no'/>` and `<filetransfer enable='no'/>` where supported, a local-only display transport, `autostart` disabled as a separate live libvirt property, and the one approved USB identity. It should reject external XML entities and fail on unknown security-relevant elements or unsupported libvirt schema versions. Validation of static XML is a precondition, not proof of runtime QEMU arguments or USB identity.

The display transport and minimum virtual devices require a disposable guest usability check before any live migration. Do not infer that omitting a `spicevmc` channel alone disables every clipboard/file path.

## 3. Legacy-profile migration and contradictions

| Current material | Proposed status | Contradiction and treatment |
| --- | --- | --- |
| `vm-profiles/trusted-workstation/` | `INCOMPATIBLE_WITH_TWO_DOMAIN_MODE` | Daily-driver prose plus NAT, virtiofs, and SPICE clipboard. Retain as historical example with prominent non-production banner; remove recommendation as current daily guidance. |
| `vm-profiles/untrusted-analysis/` | `LEGACY` | Calls the network isolated while its XML contains `<forward mode='nat'/>` and virtio-net. Banner must say NAT is external access and incompatible with daily two-domain mode. Correct the misleading isolation claim. |
| `vm-profiles/network-lab/` | `LAB_ONLY` | Multiple NAT networks and virtual NICs require a separately isolated lab environment or an explicitly reviewed mode outside the daily two-domain workflow. Do not autostart its networks on the control host. |
| Future `vm-profiles/work-domain/` | `CURRENT` | Only production daily profile, after approval and structured validation. |

The current [VM threat models](VM_THREAT_MODELS.md) call the old trusted profile recommended for daily use, [KVM security guidance](KVM_SECURITY.md) recommends `virt-manager`/`virsh` and NAT zones, and [firewall guidance](FIREWALL.md) recommends libvirt-managed NAT. Those instructions must gain explicit historical scope when the production profile lands. Preserve the examples for research; static CI must check status markers and parse the production XML so a banner cannot stand in for a control. Existing `nftables/workstation.nft` uses `flush ruleset` and output policy `accept`; it remains an incompatible historical example until a reviewed migration.

## 4. Read-only isolation verifier

Design `scripts/verify-control-domain-isolation.py` with `--expect offline|guest|maintenance` and human/JSON output. Python matches the existing evidence collector and allows structured parsing and fixture injection. The executable entry point must perform reads only: no `virsh` mutation, `nmcli` mutation, `nft` mutation, sysctl writes, link changes, service action, USB binding, or persistent state write. It may need elevated *read* access to `/proc`, nft, libvirt, and USB sysfs; inability to read is `UNKNOWN`. Fixture mode consumes a versioned observation bundle and labels every result `synthetic` so it cannot be mistaken for live ThinkPad proof.

Collectors should use bounded timeouts and structured output where available: IPv4/IPv6 addresses, routes and all policy tables/rules; interface/link/bridge and network namespace inventories; association/rfkill and the actual network manager; per-link DNS; full nft ruleset and hook ownership; forwarding sysctls; listeners; libvirt domains, networks, autostart, inactive/live XML; QEMU process argv, UID/GID, capabilities, namespaces, security label, seccomp, file descriptors; USB sysfs path and driver binding; KSM and IOMMU evidence. Inventory *all* running QEMU processes, including session and raw launches where visible. Normalize version-specific formats in collectors, then evaluate a stable typed observation model. Do not treat `virsh net-list` alone as proof that no active NAT/masquerade rules remain.

| Expectation | Required machine predicates |
| --- | --- |
| `offline` | Guard intact; no external IPv4/IPv6 or policy/DNS route, Wi-Fi association, unexpected egress NIC, NAT/masquerade, forwarding, bridge forwarding, guest ownership, external USB/IP listener, or remote management/display listener |
| `guest` | Offline host predicates; exactly approved guest running; inactive and live XML conform; one approved USB hostdev currently detached from host network driver and owned by QEMU; no virtual NIC/NAT/bridge, agent, remote display, or extra device; QEMU confinement predicates; KSM off, IOMMU active, nested policy satisfied |
| `maintenance` | All QEMU guests stopped; approved adapter host-bound; live, unexpired authorization; host routes/DNS and output allowance only on that adapter; no forwarding, NAT, second NIC, or unexpected listener |

Each check reports `PASS`, `FAIL`, `WARN`, `UNKNOWN`, `NOT_APPLICABLE`, or `MANUAL_TEST_REQUIRED`, plus a redacted reason and evidence source. Exit `1` for any required `FAIL`, otherwise `2` for a required `UNKNOWN`, `WARN`, or incomplete manual gate, otherwise `0`; bad invocation or inability to run the verifier itself is `3`. Collectors must distinguish a subprocess failure (`UNKNOWN`) from a successfully empty result. Guest Internet is `MANUAL_TEST_REQUIRED` until trusted guest-side evidence exists; a real `--expect guest` report cannot return overall `0` while that required proof is absent. Fixture tests may assert that the machine predicate evaluator accepts a synthetic valid guest state, but must not label the physical host verified.

Default output should contain statuses, counts, stable check IDs, and redacted evidence references. Remove MACs, SSID/BSSID, IPs unless needed to classify scope, USB serials, hostnames, usernames, private paths, and credentials. JSON schema and collection metadata should record source, time, permissions, timeout, and whether data are synthetic. Never follow untrusted symlinks into privileged output locations.

## 5. Privilege and ordinary-user bypass model

Before setting policy, collect the actual host operator groups, `/dev/kvm` and `/dev/bus/usb` ACLs, libvirt system/session socket owners and modes, libvirt ACL/polkit rules, NetworkManager polkit rules, USBGuard IPC, sudoers, QMP socket permissions, virt-manager paths, and systemd service controls. The repository contains no live proof of these values. Document the minimum operator actions needed: status, start/stop approved guest, request timed maintenance, and recover locally. Ordinary desktop use should not require a general root shell or full `libvirt`/`kvm` group authority.

The target is a narrow root-owned `lockdown-net status|offline|guest|maintenance` interface. Mutations serialize under one root-owned lock, deny egress first, verify current observations, make one state change, reverify, log a redacted result, and return nonzero on any uncertainty. Direct `virsh`, virt-manager, NetworkManager, USBGuard, QMP, systemd, and device ACL operations by the ordinary user must be denied or unable to grant physical egress. Audit `qemu:///session` as well as `qemu:///system`; hiding a desktop shortcut is not access control. Restrict `/dev/kvm` and USB device access where practical, but ordinary users can still run software emulation; the meaningful guarantee is that it cannot acquire the approved adapter or external route. Root override is outside the threat model.

Permission changes require evidence of installed distribution defaults and desktop needs. Do not assume a polkit prompt is equivalent to authorization, or that removing a Unix group blocks every libvirt connection. [Libvirt ACL/polkit documentation](https://libvirt.org/aclpolkit.html) supports fine-grained API authorization, but the actual driver and Unix socket boundary must be verified on this host.

## 6. Dedicated nftables guard

Create a separately owned guard table and transaction files after approval. Keep the historical `nftables/workstation.nft` out of production loading; its global flush would delete the guard. The offline transaction installs `inet` output/input/forward and `bridge` output/forward base chains with deny behavior. Host loopback may remain. All non-loopback host IP output, external input, IPv4/IPv6 forwarding, bridge forwarding, and guest NAT must be denied in `SAFE_OFFLINE`, `GUEST_EGRESS`, `TRANSITION`, and `ERROR`. Maintenance may permit host output only on the currently verified MT7921U interface with a live lease; no guest, second uplink, forwarding, NAT, or new external inbound sessions.

Use atomic nft transactions for guard state changes. A transition may narrow or replace allowances but never delete the guard as an intermediate state. An nft `drop` verdict cannot be reversed by another base chain's `accept`; an `accept` verdict is not globally final. Base-chain family, hook, and priority must be checked against libvirt/firewalld/NetworkManager shared mode and iptables-nft on the actual host. There must be one documented owner for the table and an integrity check after daemon reloads. Rule survival after controller exit is required. A candidate lease mechanism is a kernel-expiring nft set entry naming the approved interface while the base-chain policy remains drop; validate the installed kernel/nft timeout semantics and crash behavior before selecting it. A userspace watchdog can disconnect stale association but cannot be the sole enforcement of expiry. Keep a local offline recovery path. Do not claim `Before=network.target` alone makes boot fail closed.

Consider `netdev` egress as an optional L2 backstop: it can inspect all ethertypes, including ARP, but its base chain is device-bound. Hotplug/re-enumeration may create a new name before a per-device chain attaches, and maintenance must still allow L2 discovery on exactly the approved adapter. Adopt it only if the installed kernel/nft version and hotplug ordering yield a proven fail-closed binding; otherwise use the `inet`/`bridge` guard and explicit link quarantine, and record the remaining L2 limit. A second interface must never inherit a maintenance allowance by name reuse. [nftables documents the hooks and verdict semantics](https://netfilter.org/projects/nftables/manpage.html).

## 7. Libvirt lifecycle gate

Work guest and every historical NAT network autostart must be off in daily mode. A short `qemu prepare begin`/`start begin` hook should reject unauthorized start before guest creation. It reads a root-owned, short-lived, single-use token under `/run/lockdown-net/`; the token binds domain UUID, immutable XML digest, adapter physical identity, requested mode, and deadline. The hook must consume it atomically and compare the XML handed to the hook with the approved digest. It must be bounded, local, and fail closed, and **must not call back into libvirt** while libvirt waits for it. [Libvirt hook documentation](https://libvirt.org/hooks.html) confirms pre-start veto and warns of callback deadlock. Hook installation/restart behavior must be tested on the installed version.

The hook is one gate, not the sole authority: socket ACLs/polkit restrict direct domain definition, editing, start, hotplug, and network starts; the controller checks observed firewall/device/guest state before and after launch. A replayed/expired token, changed XML, missing guard, unexpected network, or contradictory state denies start. Domain shutdown and QEMU crash leave the host guard closed even if libvirt reattaches USB. `started`, `stopped`, and `release` notifications are reconciliation signals, not permission to open egress. Reject direct `virt-manager`/`virsh` starts and network autostart in disposable tests.

## 8. QEMU confinement requirements

For the live work QEMU PID, require nonzero UID/GID and the expected distribution service account, an active per-domain enforcing AppArmor/sVirt profile, acceptable seccomp filter and `NoNewPrivs` state where supported, and a reviewed effective capability set. Inspect `/proc/PID/status`, `/proc/PID/attr/current`, generated label, executable/argv, namespaces, and open descriptors; distinguish read failure from absence. The checked-in [libvirtd example](../apparmor/usr.sbin.libvirtd-local) is a complain-mode daemon example, not evidence that a QEMU domain is confined. [Libvirt describes per-domain AppArmor profiles](https://libvirt.org/drvqemu.html); [QEMU describes unprivileged execution, LSMs, cgroups, and seccomp](https://www.qemu.org/docs/master/system/security.html).

Prove denial of access to host home, MOK private keys, recovery directories, unrelated VM images, arbitrary host devices, and management sockets using the generated policy plus disposable negative probes. Merely failing to see an open FD does not prove access is denied. QMP is privileged: Unix/local only, restricted to root/libvirt-authorized principals, absent from guest channels and TCP, with actual socket owner/mode checked. Exact capability, seccomp, and `NoNewPrivs` expectations require the installed Ubuntu/libvirt/QEMU version; unsupported or inaccessible evidence stays `UNKNOWN`, never assumed safe.

## 9. SPICE and viewer confinement

The guest needs a local interactive desktop. Proposed XML explicitly disables clipboard and file transfer and uses local-only graphics with no TCP VNC, SPICE, or WebSocket listener. Validate static XML and live QEMU argv/socket inventory; a `listen='127.0.0.1'` TCP endpoint still needs a separate justification and is not the default. No guest agent or automatic USB redirection is ambient. The viewer is a guest-controlled parser on the host: inventory the actual `virt-viewer`/`remote-viewer` process, sockets, and filesystem accesses before proposing a sandbox/AppArmor profile. A disposable complain-mode trial should establish the minimum display/audio/session sockets and writable paths while denying network, SSH/GPG keys, MOK material, recovery data, and arbitrary home reads. Enforce only after UI, input, suspend, and recovery are proven on the ThinkPad.

## 10. Storage, resources, and crash dumps

Compare qcow2 in a host filesystem, dedicated raw LV, and LVM-thin for host root-space exhaustion, access labeling, snapshots, rollback, performance, and recovery. A compromised guest can fill its allocated disk; host root must have a separately bounded failure domain or measured free-space reserve and alert. QEMU access to unrelated images/backups must be denied. No storage migration is part of this phase.

Size RAM, vCPU, disk growth, I/O, process count, open files, and log volume from workload evidence; use libvirt/cgroup controls that preserve a local recovery margin. Keep KSM off and verify it at runtime. Verify IOMMU and nested virtualization policy separately; a Kconfig setting is not runtime proof. Review supported `<memory dumpCore='off'>` behavior to avoid collecting guest RAM in host crash dumps by default, documenting the loss of post-crash debugging evidence. Do not choose arbitrary numeric limits before measurement.

## 11. Failure behavior

| Event | Required outcome |
| --- | --- |
| Guard load fails at boot | Network manager, Wi-Fi supplicant, libvirt and guest start blocked by real unit dependencies; local console recovery available |
| Verifier command fails or times out | `UNKNOWN`, overall nonzero; no transition grant |
| QEMU exits, guest crashes, libvirt restarts, USB reattaches | Host output remains denied; reconcile to offline/error; no automatic association |
| USB unplug/replug or device identity changes | Quarantine; no automatic ownership or name-based maintenance allowance |
| Controller dies or lease expires | Kernel guard remains; lease enforcement closes maintenance output; state reconciled |
| Firewall daemon reload or NAT rules appear | Guard integrity check fails; controller blocks guest/maintenance grant and records error |
| State/token disagrees with routes, association, XML, or process | Observed evidence wins; enter `ERROR`, deny egress |

Boot dependency design must name the actual installed NetworkManager/iwd/wpa_supplicant, libvirt modular daemon/socket, USB event, and desktop services after inventory. A passive `network.target` ordering line is insufficient. If systemd cannot guarantee the guard precedes a given activation path, that path stays disabled until a stronger gate exists.

## 12. Test strategy and CI

Each implementation component starts with a failing fixture, then the smallest change, regression run, diff review, and an isolated commit. Tests parse actual XML/nft structures or exercise disposable namespaces; they do not grep comments for disabled features. The Linux CI suite should cover production XML schema and prohibitions, legacy status consistency, verifier observation parsing and exit codes, hook/token replay/expiry/XML changes, and nft syntax plus packet-path behavior in disposable namespaces. It must not claim physical ThinkPad state.

Verifier fixtures include valid offline/guest/maintenance observations; stale IPv4/IPv6/policy routes, association without route, DNS, NAT/masquerade, forwarding, unexpected NIC, USB/IP on `0.0.0.0` or `::`, remote libvirt/SPICE/VNC, guest virtio NIC/NAT/agent, QEMU root, AppArmor complain/unconfined, absent seccomp, KSM on, IOMMU unavailable, and every command-failure-to-`UNKNOWN` path. Guard fixtures cover host output, IPv4/IPv6 and bridge forwarding, interface-restricted maintenance, stale routes, libvirt NAT coexistence, controller exit, and failed transition without flush. Bypass fixtures cover direct starts, autostart, unauthorized USB, token expiry/reuse, XML mutation, and stale-state contradictions. CI can prove repository behavior and fixture behavior only.

## 13. Deployment gates

**Gate A: repository implementation instruction received.** The subsequent owner instruction describes this as implementation of the approved architecture and requests a separate `thinkpad-two-domain-enforcement` branch from `windows-codex`. Continue in small independent commits. This instruction does not approve live firewall, network-manager, USB, AppArmor, libvirt, or kernel mutation.

**Gate B: disposable Linux validation.** Require XML/nft syntax, fixture matrix, hook behavior, CI and negative paths before proposing live installation. Record package versions and unresolved checks.

**Gate C: separate owner-supervised ThinkPad changes.** Require local console, current configuration backups, verified fallback boot/recovery, exact Wi-Fi identity, and one reversible change at a time. Installing nft rules, editing NetworkManager/USBGuard/AppArmor/polkit/libvirt/systemd, changing groups, binding the adapter, or starting the production guest remains owner-gated. No audit12 kernel candidate or audit11 effective-config change belongs to this phase.

## 14. Rollback

Before a live stage, export active firewall, routes, network manager profiles, USBGuard, libvirt XML/networks/autostart, AppArmor and group/polkit state, plus guest storage metadata. Preserve the signed audit11 and stock boot paths. Rollback from any failed stage begins with offline deny active, guest stopped, and adapter quarantined; restore one service/policy component at a time from local console and rerun the read-only verifier. Do not use `nft flush ruleset` as a recovery shortcut, and do not re-enable an old NAT profile as an automatic daily fallback. Test actual restoration in a disposable environment before live use.

## 15. Residual risks and open evidence

KVM/QEMU/USB/display parser escapes, host-kernel or firmware compromise, microarchitectural channels, malicious root, device identity spoofing, and physical attack remain. A root-owned controller narrows ordinary operation; it cannot secure a hostile host root. Windows repository review cannot establish actual NICs, routes, firewall hook precedence, service ordering, libvirt ACLs, QEMU credentials, generated AppArmor policy, viewer access, storage limits, or Wi-Fi behavior on the ThinkPad. Keep each as `UNKNOWN` until live evidence and owner tests exist. Owner validation must include reboot, guest/QEMU crash, libvirt restart, USB re-enumeration, suspend/resume, maintenance expiry, listener exposure, and both directions of the egress exclusivity claim.
