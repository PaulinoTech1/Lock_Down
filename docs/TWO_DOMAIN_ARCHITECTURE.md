# Two-Domain Workstation: architecture proposal

**Status:** design for owner review; no runtime change authorized by this document.
**Baseline:** `winddows-codex` at `489879adb00b518b122c931fe35a147cb1617733`, reviewed 30 September 2026 from a Windows checkout.
**Priority:** host isolation, minimal host attack surface, guest containment, recovery, performance, battery efficiency, convenience.

This proposal supersedes the **trust assumption** and integration defaults of the existing `trusted-workstation` daily-driver profile. It does not delete the historical `untrusted-analysis` or `network-lab` profiles. The system is Qubes-inspired compartmentalization on Linux/KVM/libvirt; it is **not Qubes-equivalent** and has no separate sys-net, sys-usb, storage, firewall, or service qubes.

## 1. Threat model and evidence boundary

Assume the work guest is fully compromised: guest root, arbitrary code execution, full control of guest networking, knowledge of KVM, deliberate virtual-device fuzzing, and malformed traffic to every reachable host interface. The asset is the control host: its filesystem, MOK/Secure Boot and recovery material, TPM-related material, SSH/GPG keys, clipboard, user data, network control, devices not assigned to the guest, libvirt APIs, and privileged services. A guest compromise must not grant administrative control or routine read/write access to these assets.

The host, boot chain, hypervisor, and firmware remain trusted in this model. A guest escape is explicitly possible. Confidentiality of a **running** guest from its host is not a design claim. A compromised guest can destroy its own files and credentials or attack remote services with the user's guest identity. Host-side rollback cannot undo exfiltration.

**Observed versus proposed:** The [audit11 owner runbook](AUDIT11_OWNER_RUNBOOK.md) records Secure Boot enabled, integrity lockdown, mapper-backed root, two diskless KVM boots, and a transient Ubuntu guest reaching serial login and ACPI shutdown. It also records incomplete guest login/network/agent/workload, physical hardware, suspend, and fallback checks. This Windows review cannot establish current Linux host sockets, routes, QEMU identity, AppArmor state, USB bindings, or performance. All target controls below are **proposed** until measured on the ThinkPad. The existing [firewall sample](../nftables/workstation.nft) is an example with output policy `accept`, not evidence of a networkless host; the [AppArmor local file](../apparmor/usr.sbin.libvirtd-local) is an example in complain mode, not an enforced QEMU profile.

## 2. Trust boundaries and domains

```text
                 physical input and display                 external network
                         |                                         |
                         v                                         v
  +-----------------------------------------------+     +------------------------+
  | DOMAIN 0: CONTROL HOST                        |     | MT7921U USB Wi-Fi      |
  | boot / LUKS / Secure Boot / recovery           |     +-----------+------------+
  | KVM + unprivileged QEMU + local VM viewer      |                 |
  | libvirt lifecycle / snapshots / updates       |                 | exclusive assignment
  | no routine Internet apps or guest user files  |                 v
  | no external route in normal mode              |     +------------------------+
  +---------------------+-------------------------+     | DOMAIN 1: WORK GUEST   |
                        |                               | browser / dev / email    |
             KVM, minimal virtual devices,             | cloud / files / keys     |
             local display and input only               | Internet-facing work    |
                        +------------------------------>| assumed root-compromised |
                                                        +------------------------+
       Prohibited ambient bridges: host filesystem, clipboard, management API,
       host credentials, automatic USB, host Internet forwarding.
```

The host performs boot, disk unlock, virtualization, local presentation, lifecycle, backup, updates, and recovery. The guest performs all routine browsing, email, development, cloud, and document work. The long-lived topology is one host and one work guest; temporary recovery overlays are not new permanent domains. Physical input/display remain on the host and therefore must not be treated as risk-free. The host viewer parses guest-controlled display output; input is sent toward the guest.

## 3. Normal-state architecture

Target invariant while the work guest runs:

| Control host | Work guest |
| --- | --- |
| No external Wi-Fi association, external default route, Internet DNS, or externally reachable service; verify IPv4 **and** IPv6. | Internet via exclusively assigned MT7921U if feasible. |
| Local VM presentation and `qemu:///system` administration from the host only. | No libvirt, Docker, host systemd, firewall, package-manager, snapshot, or host power API. |
| No routine browser, email, development, documents, cloud login, or password-manager use. | Owns everyday apps, user files, and most credentials. |
| No guest filesystem mount, shared directory, clipboard, file transfer, or guest agent by default. | Own storage; cannot read host home, signing keys, or recovery files. |
| QEMU unprivileged and confined; KSM off, active IOMMU, nested virtualization off if supported and verified. | Only required virtual devices; no automatic USB attachment. |

The host may retain local loopback and necessary non-routed kernel interfaces. “No default route” alone is insufficient: check static routes, IPv6 router advertisements, DNS, associations, forwarding, bridges, listeners, USB device ownership, and reachability from the guest. A guest-owned USB radio still traverses the host USB core and QEMU device model; it does not remove host kernel exposure entirely.

## 4. Maintenance-state architecture

**Only one domain owns the Wi-Fi function at a time.** Maintenance is an explicit state transition, performed at a local console with a known-good signed fallback kernel and offline recovery instructions available:

1. Stop the work guest and confirm its QEMU process has exited; do not transfer the radio while guest I/O is active.
2. Confirm the MT7921U is released. Rebind it to the host under the approved USBGuard/device policy.
3. Enter a visibly indicated host-maintenance state, enable only the network services needed for update retrieval, and record active interface, IPv4/IPv6 routes, DNS, listeners, and firewall state.
4. Update the host kernel, QEMU/libvirt, firmware and packages; verify signatures, Secure Boot state, intended kernel/fallback, and service health. Avoid routine account logins or browsing.
5. Disable host connectivity and associated services, remove external routes and DNS, disconnect the Wi-Fi association, and release the device from the host network driver.
6. Run the **read-only** isolation verifier; only after PASS may the work guest start and claim the radio. If verification fails or is UNKNOWN, remain in maintenance with the guest stopped or use the documented recovery path. Never silently call this normal mode.

The future `scripts/verify-control-domain-isolation.sh` must be observational and produce `PASS`, `FAIL`, `WARN`, `UNKNOWN`, or `MANUAL_TEST_REQUIRED` per check. It should inspect both IP families, interfaces, associations, sockets, libvirt and display listeners, firewall and bridge paths, QEMU UID/GID/capabilities/seccomp/AppArmor, open files/device nodes, guest XML and live devices, KSM, IOMMU, USB assignment, and nested virtualization. It must distinguish “no guest running” from “running guest verified.” An interrupted transition cannot be made fail-closed by documentation alone; stage 7 must design a durable state marker, local recovery, startup gate, and crash/reboot behavior before deployment.

## 5. Host attack-surface inventory

| Host surface | Current evidence | Target / audit question |
| --- | --- | --- |
| Network services and sockets | Example nftables output accepts egress; live state unknown. | Enumerate TCP/UDP/Unix sockets, owning processes, externally and guest-reachable addresses; remove unnecessary services after dependency review. |
| External routes, DNS, Wi-Fi | [USB guidance](USB_SECURITY.md) identifies the MT7921U as the current sole network path; runtime unknown. | No host Internet path in normal mode; test IPv4/IPv6, stale routes, resolver, and association. |
| libvirt management | Existing examples use `qemu:///system`; actual socket permissions unknown. | Local Unix access for a small admin set; no TCP or guest-mounted socket. Audit `libvirtd` versus modular daemons and their dependencies on installed version. |
| QEMU and helper processes | Historical guest boot proves operation, not current confinement. | Non-root UID, per-VM AppArmor confinement, no capabilities or unrelated file/device access; include virtiofsd, swtpm, dnsmasq and viewer only if actually used. |
| Desktop/autostarts | Unknown on Linux host. | Inventory and disable only unneeded network/cloud/indexing/updater integrations; retain required display, accessibility, input, and local recovery. |
| Host credentials/data | Existing docs do not prove separation. | Keep MOK private key, LUKS recovery, TPM material, sudo/PAM, host SSH/GPG and backup keys outside QEMU readable paths and guest transfer flows. |
| USB/PCI devices | Audit12 preserves USB/IP and USB hardware support. | Explicit ownership allowlist; host input/auth/recovery devices never auto-attach. |
| Storage/backup | Host LUKS root reported; guest image layout not finalized. | Guest block storage opaque to host desktop; backups inaccessible to guest and QEMU writable scope. |

No package removal follows from this table. Record actual service ownership and dependencies before changing units or installed software.

## 6. Guest-to-host channel inventory

“Default” means proposed runtime exposure, **not** current measured state. “Host parser” includes host kernel, QEMU, helpers, and desktop components handling guest-controlled input. A `No` in “required” means absent from the normal guest; compiled support may remain.

| Channel | Direction | Host component / privilege | Guest component | Availability | Attack surface; performance or operational value | Required? / default / remove or narrow |
| --- | --- | --- | --- | --- | --- | --- |
| KVM ioctl | QEMU -> host kernel; guest exits -> QEMU/KVM | `/dev/kvm`, KVM kernel; QEMU unprivileged | vCPU state | Always while running | Essential acceleration; guest can exercise KVM paths | Yes / on / constrain QEMU and patch kernel |
| QEMU virtual devices | Both | QEMU device parsers, helper processes | device drivers | Per configured device | Boot/UI/I/O; each model adds parser | Yes / minimal set / remove unused legacy devices |
| SPICE display/input | Guest pixels -> viewer; host input -> guest | QEMU SPICE server + local viewer, user privilege | display/input drivers | Interactive session | Necessary desktop; viewer/server parse guest output | Yes / local Unix only / disable auxiliary features |
| SPICE clipboard | Both | SPICE agent/server/viewer, host clipboard | `spice-vdagent` | Currently trusted profile enables | Convenience; credential exfiltration and content injection | No / off / remove agent channel or explicitly disable copy-paste |
| SPICE agent/file transfer | Both | SPICE server/viewer and file-transfer helper | `spice-vdagent` | Existing trusted profile includes `spicevmc` | Resize/convenience; file and clipboard bridge | No / off / remove channel and disable transfer |
| QEMU guest agent | Guest -> host, host -> guest | libvirt/QEMU agent socket; host management client | `qemu-guest-agent` | Audit11 test exposed a channel; no response observed | Shutdown/freeze/status; guest-supplied data reaches management | No by default / absent / justify specific task before adding |
| virtiofs | Both | `virtiofsd`, QEMU, host VFS under configured export | virtiofs driver | Trusted profile persistent share | Fast shared files; direct guest access to host tree | No / absent / remove daily export; retain compiled capability |
| 9p | Both | QEMU 9p server, host VFS | 9p driver | Not required by target | Shared files, weaker performance than block storage | No / absent / no export |
| virtio-net | Both | QEMU network backend, possibly kernel | guest NIC driver | NAT fallback or narrow host-only channel | Network performance; network parser | No for direct Wi-Fi / absent unless approved path |
| vhost-net | Both | Host kernel vhost-net and TAP | virtio-net descriptors | Only if enabled for a virtio NIC | Higher throughput; guest descriptor handling in kernel | No normal direct-Wi-Fi path / unused; do not cut Kconfig |
| TAP/bridge | Both | Host kernel networking, libvirt | virtio NIC | NAT or host-only option | Routing/transfer; host IP and L2 exposure | No direct-Wi-Fi default / absent; isolate if needed |
| libvirt NAT | Guest -> host -> Internet; replies back | libvirt, host IP stack/firewall | virtio NIC | Compatibility fallback | Easy networking; Internet-facing host stack | No / off / explicit fallback only |
| Host DNS/DHCP | Guest -> host | libvirt `dnsmasq` if network defines it | DHCP/DNS client | Libvirt NAT or some isolated nets | Addressing; guest-reachable host parser | No default / absent; audit any fallback network |
| USB redirection | Both | QEMU/SPICE USB stack, host USB core | guest USB driver | Historical per-session option | Device access; broad attach/agent path | No automatic redirection / off; specific device approval only |
| Direct USB hostdev | Both | Host USB core, libvirt/QEMU USB emulation | guest MT7921U driver | Proposed while guest runs | Guest Internet without host IP stack; USB/QEMU attack surface remains | Conditional yes / only Wi-Fi VID:PID plus stable identity; verify detach |
| USB/IP | Both over TCP/IP | `usbipd`/USB core/stub/VHCI, host IP stack | USB/IP client or exported device | Kernel support compiled; service state unknown | Required workflow, but network daemon and device parser exposure | Capability yes / runtime off except approved session |
| virtio block/storage | Both | QEMU block layer, host file/block I/O | guest virtio-blk/scsi | Always while running | Fast persistent disk; guest I/O reaches QEMU and kernel | Yes / one minimal controller; constrain image access |
| Audio output | Guest -> host | QEMU/SPICE audio backend, host audio server | guest audio driver | If daily use requires | Useful playback; parser and host audio service | Conditional / output only; verify needed backend |
| Microphone | Host -> guest | host audio capture backend | guest audio input | No default need | Calls; host microphone privacy exposure | No / off; explicit temporary exception |
| virtio-rng | Host entropy -> guest | QEMU RNG backend/host RNG | guest virtio-rng | Candidate | Improves guest entropy availability; small device surface | Conditional / retain if justified and measured |
| Serial console | Both | QEMU PTY/Unix, local host terminal | guest serial driver | Recovery/debug only | Diagnostic access; guest output reaches host terminal | Conditional / local on demand, no TCP |
| libvirt sockets | Host admin -> libvirt; must not cross | privileged libvirt daemon or modular sockets | none | Host only | Full VM management; compromise is high impact | Host required / local restricted; guest zero access |
| AppArmor/sVirt | Host policy around QEMU | kernel LSM, libvirt profile generator | none | Always for guest | Reduces blast radius; no guest API by itself | Yes / enforcing; verify live label and denials |

**Required architectural review of every channel:**

| Channel | Required? | Default | Host parser exposed | Performance value | Security cost | Proposed control |
| --- | --- | --- | --- | --- | --- | --- |
| KVM ioctl / virtual devices | Yes | KVM + minimal machine | Kernel KVM; QEMU | Essential / high | Escape surface | Patch; minimize devices; confine QEMU |
| SPICE display/input | Yes | Local only | QEMU SPICE; viewer | Essential UI | Guest graphics data reaches host | Unix/local, no remote listener |
| Clipboard / SPICE agent / file transfer | No | Off | SPICE server/viewer/agent | Convenience | Secret and file bridge | Remove agent channel, disable features |
| QEMU guest agent | No default | Absent | QEMU/libvirt agent path | Management convenience | Guest responses feed host management | Add only for a measured operation |
| virtiofs / 9p | No | Absent | `virtiofsd`/QEMU/VFS | Fast sharing | Host tree exposure | No persistent export |
| virtio-net / vhost-net / TAP | Conditional | Absent with direct Wi-Fi | QEMU or kernel network backend | Network speed | Guest packet/descriptor path into host | Host-only channel only if justified; vhost off there |
| libvirt NAT / DNS / DHCP | Fallback only | Off | Host stack, firewall, `dnsmasq` | Easy network setup | Host Internet path and guest service exposure | Separate reviewed fallback |
| USB redirection | No automatic | Off | QEMU/SPICE/USB core | Device convenience | Broad device path | Device-specific, on demand |
| Direct USB Wi-Fi | Conditional target | MT7921U only | USB core + QEMU USB | Direct connectivity | USB parser and assignment risk | Exclusive binding, USBGuard review, suspend tests |
| USB/IP | Workflow capability required | Service off | `usbipd`, USB/IP kernel, TCP | Remote-device workflow | Host network daemon and device exposure | Isolated path only, per-device allowlist/session |
| virtio block | Yes | On | QEMU block + kernel I/O | High | Guest block commands reach host | Opaque disk, strict QEMU access |
| Audio / microphone | Output conditional; input no | Output if needed; mic off | QEMU/SPICE/audio server | Desktop utility | Media parser; privacy | Minimal output backend, input exception |
| virtio-rng / serial | Conditional | RNG if needed; local serial on demand | QEMU/kernel RNG; terminal | Entropy/recovery | Small extra parsers | Confirm need and Unix/local scope |
| libvirt sockets | Host only | Guest absent | libvirt management | VM lifecycle | Full host control if exposed | Unix permissions; never guest mount/network |
| AppArmor/sVirt | Yes | Enforcing | Kernel LSM/libvirt | Containment | Misconfig can fail open | Verify actual profile and QEMU access |

## 7. Network architecture comparison

| Option | Guest Internet path | Host exposure | Benefit | Main costs / acceptance test |
| --- | --- | --- | --- | --- |
| **A. Direct libvirt USB assignment** | MT7921U -> host USB core -> QEMU USB model -> guest Wi-Fi stack | Host USB enumeration and QEMU USB; host Wi-Fi/IP driver should be detached in normal mode | No host Internet-facing IP stack or NAT path; guest controls Wi-Fi; simple two-domain topology | Must prove exclusive binding, USBGuard compatibility, guest driver/firmware, reconnect after suspend, power, throughput, and maintenance recovery. Host still sees USB descriptors. |
| **B. USB/IP on isolated host-only transport** | Device export/import via USB/IP TCP between host and guest, with a host-only interface | Host USB/IP daemon, TCP/IP transport, virtual NIC/TAP and potentially host DNS/DHCP, plus USB core | Required remote USB workflows; may help specific devices when direct assignment cannot meet workflow | Usually more exposed for a local adapter than A. Any listener must be reachable only on the isolated path and approved guest, never external interfaces; validate actual `usbipd` bind semantics/version and firewall behavior. No default service. |
| **C. Host NAT/TAP** | MT7921U -> host Wi-Fi/IP -> NAT/firewall/TAP -> guest virtio-net | Host radio driver, IP stack, firewall, libvirt bridge, `dnsmasq`, QEMU/vhost as configured | Mature compatibility path; may survive USB assignment limitations | Violates the normal networkless-host goal; explicit fallback only, with guest-to-host service and LAN negative tests. Not silently called equivalent isolation. |

Libvirt's [domain XML](https://libvirt.org/formatdomain.html) supports USB `hostdev` assignment and states USB devices are detached from the host on guest start and reattached on exit/hot-unplug. That is mechanism documentation, not proof of the MT7921U behavior on this laptop. Libvirt's [network XML](https://libvirt.org/formatnetwork.html) says NAT traverses the host IP routing stack; an “isolated” network can still let guests reach the host and can run DNS/DHCP. A network without `<forward>` is therefore not, by itself, a host isolation proof.

## 8. Wi-Fi ownership decision

**Preferred design, conditional:** Assign only the external MT7921U to the work guest by direct USB hostdev in normal mode. It must be released by the host network driver and blocked from host autoconnect; assignment is rejected if the host retains an external route, radio association, or guest-reachable service. Match the physical device using a stable, reviewed identity; VID:PID `0e8d:7961` alone may match another identical device, while bus/port can change after reconnect. Do not pass the host keyboard, mouse, recovery media, or authentication token.

Acceptance requires owner-observed guest Wi-Fi connectivity, loss/reconnect and suspend/resume behavior, stable handoff to maintenance mode, USBGuard compatibility, guest driver support, and a local-console fallback. If any criterion fails, keep the current NAT path as an explicitly weaker temporary compatibility mode while investigating. Do not disable host networking or change USB binding on the basis of this design alone. The [existing USB policy](USB_SECURITY.md) currently treats this adapter as host-owned; that operational instruction must be revised **only after** a validated transition and owner approval.

## 9. USB/IP runtime policy

Preserve `CONFIG_USBIP_CORE=y`, `CONFIG_USBIP_VHCI_HCD=y`, and `CONFIG_USBIP_HOST=y` as required by the owner and recorded in [audit12 stage 0](audit12/STAGE0_REVIEW.md). Compiled capability does not imply a running daemon or an attached device. Inventory actual services, listening addresses, virtual hubs, import/export sessions and device IDs on the Linux host before modifying policy. The kernel [USB/IP protocol](https://docs.kernel.org/usb/usbip_protocol.html) uses a server/client TCP connection that remains open for USB request traffic; it is an explicit host network and USB attack path.

Runtime target: service disabled and no exported devices normally. For an approved session, use a dedicated isolated host-only transport, explicit guest address/firewall rule, per-device allowlist, and timed/manual teardown. Do not expose `usbipd` on external interfaces or `0.0.0.0`; verify the installed daemon's actual bind options and listener after start. If interface binding is unsupported, fail closed with a host firewall and namespace arrangement proven by negative tests, or do not activate the session. No automatic export; host input, host security tokens, boot/recovery media, and the maintenance Wi-Fi path are excluded. Direct USB assignment remains preferred for this local Wi-Fi adapter unless USB/IP demonstrates a specific needed advantage.

## 10. Display and graphics policy

Use a local viewer and a local Unix/libvirt connection. The guest requires video, keyboard and pointer; it does not require a network-facing SPICE/VNC listener, clipboard, file transfer, or a SPICE agent solely for convenience. Inspect both inactive and live XML, QEMU arguments and `ss` output; the absence of a `<listen>` line is not enough evidence. If SPICE is used, explicitly disable clipboard and file transfer because libvirt [documents them as enabled by default](https://libvirt.org/formatdomain.html). Remove `spicevmc` unless a separately reviewed essential function requires it. Check any display resize/input features against the actual installed libvirt/QEMU stack.

Start with virtio-gpu 2D and no host GPU render node exposed to QEMU. Test normal desktop responsiveness. Virgl/3D is a named performance exception: document renderer/device access, guest-controlled graphics parser path, benchmark gain, AppArmor change, and a one-step rollback to 2D. The local-only display rule still applies if 3D is approved. Avoid legacy video/USB/IDE devices that are not required for boot or input, based on live device inventory rather than assumptions.

## 11. Audio and microphone policy

Allow guest audio **output** only if the daily workflow needs it, with the least host audio backend and device access the installed stack supports. Record QEMU/SPICE/audio server processes and any guest-controlled decoding path. Disable host microphone capture to the guest by default. A call/recording exception is explicit, time-limited, reversible, and verified closed afterward. Do not pass unrelated physical audio devices or enable a general USB audio redirection path as a shortcut.

## 12. Clipboard policy

Clipboard sharing is off in both directions. Host clipboard content often contains passwords, recovery phrases, commands, private URLs, and tokens; a root-compromised guest can read or alter ambient clipboard data. If a future workflow needs a transfer, require a deliberate one-shot action with visible direction, size/type limits, and no background synchronization. Until that mechanism is specified and reviewed, use no clipboard bridge. Disabling one UI toggle is insufficient if another agent/channel still carries clipboard data.

## 13. File-transfer policy

The normal guest has no persistent host filesystem share: no virtiofs, 9p, host-mounted guest filesystem, drag-and-drop, SPICE file transfer, or shared `/home`, `Documents`, `Downloads`, SSH keys, Git credentials, browser data, MOK keys, or recovery directories. Development files live in the guest and sync directly to remote services from the guest.

An optional airlock is **off by default** and user-initiated. Compare a read-only, generated ISO for host-to-guest delivery with a one-shot restricted SFTP service on an isolated host-only link for the rare guest-to-host delivery. The latter adds a host network endpoint, so use a dedicated unprivileged account, fixed quarantine directory outside sensitive trees, no shell/forwarding, size and type limits, explicit enable/disable, and no automatic indexing/opening. Treat received data as hostile and scan/review offline. No custom file-transfer protocol or ambient mount is justified. Stage the airlock only after demonstrating a real workflow need and negative host-reachability tests.

## 14. Credential separation

| Credential or device | Control host | Work guest |
| --- | --- | --- |
| MOK/Secure Boot private material, LUKS/recovery passphrases, TPM administration | Host/offline recovery only; never QEMU-readable | Never present |
| Host sudo/PAM and host SSH/GPG | Host admin only; minimum use | Never copied or forwarded |
| Browser, cloud, GitHub, guest SSH/GPG and password manager | No routine account/session or copy | Guest-owned, with its own backup/recovery plan |
| Hardware authentication token | Host token stays host-owned; no automatic USB redirection | Separate approved token/function and explicit attachment only if needed |

The host must not become a credential broker for the guest. Guest compromise can steal the guest's own credentials, so remote account MFA, revocation, and recovery are still necessary. A security token's composite USB functions need inspection; assigning one function must not silently expose a host-authentication function.

## 15. Storage and snapshot design

Host LUKS provides at-rest protection for host-owned guest blocks. The QEMU process should only access the assigned guest image/volume, not the host home or backup store. The host desktop never routinely mounts guest filesystems; admin tools treat images as opaque blocks.

| Backing | QEMU/host parser surface | Performance/space | Snapshot, confinement and recovery tradeoff |
| --- | --- | --- | --- |
| qcow2 file | QEMU qcow2 metadata plus host filesystem | Sparse, compression/overlay flexibility; metadata cost | Easy external overlays and copy; protect base, cap chain length, verify backing path and sVirt/AppArmor label. |
| raw file | Simpler QEMU format plus host filesystem | Predictable I/O; sparse only if provisioned | Filesystem or external snapshot mechanism required; straightforward copy/restore, label path. |
| LVM LV | QEMU raw block path, device-mapper | Direct block I/O, fixed allocation | Host snapshot/copy required; grant only specific LV device access; avoid exposing VG broadly. |
| LVM-thin LV | QEMU raw block path, thin-pool metadata | Thin allocation and efficient snapshots | Pool exhaustion can damage availability; monitor headroom and metadata, restore-test snapshots. |

**Working choice for feasibility study:** compare qcow2 with a raw LVM-thin guest LV under encrypted host LVM. Do not claim raw/thin is automatically safer or faster; measure and include backup and out-of-space behavior. Keep a verified, immutable base or known-good backup, a rollback-capable system state, and separately backed-up persistent guest data. The guest and its QEMU UID must not be able to rewrite the recovery base/backups. Guest LUKS may protect a powered-off guest disk from separate storage loss, but **does not protect a running guest from the trusted hypervisor**. It also does not clean compromised persistent data when a system snapshot is reverted.

## 16. QEMU/libvirt confinement

Use `qemu:///system` from the host with access limited to administrators. Verify installed libvirt/QEMU versions and generated command line before proposing exact settings. QEMU must run as an unprivileged account (commonly `libvirt-qemu` on Ubuntu), with a per-VM enforcing AppArmor profile, minimal capabilities, seccomp if supported and active, and access only to its disk, firmware, assigned MT7921U, local display endpoint, and necessary device nodes. Inspect `/proc/<pid>/status`, AppArmor label, open file descriptors, capabilities, mount/device access, and helper processes. Restrict backup, MOK, recovery, host home, unrelated VM images, and management sockets outside QEMU's readable/writable scope. Do not weaken the profile to make a VM start; fix missing narrow rules and retest.

Libvirt [documents AppArmor sVirt per-VM profiles](https://libvirt.org/drvqemu.html) for `qemu:///system` when the daemon profile is loaded. QEMU [recommends unprivileged processes, LSM confinement, cgroups, and seccomp](https://www.qemu.org/docs/master/system/security.html). These are version- and deployment-dependent mechanisms, not proof that this host currently enforces them. Prefer supported libvirt configuration; do not add raw QEMU arguments merely because the offline `kvm-smoke.sh` test uses `-sandbox`. Verify the actual live launch. Use resource limits so a compromised guest cannot trivially exhaust all host memory, disk, CPU, or I/O needed for recovery.

## 17. CPU and memory policy

Baseline: KVM acceleration, host-passthrough CPU where compatible, sensible vCPU count, SMT on, normal scheduler, no blanket `isolcpus`, `nohz_full`, or `rcu_nocbs`. The documented i5-1245U has 2 P-cores, 8 E-cores and 12 logical CPUs; benchmark a starting allocation rather than assuming 4 vCPUs is optimal. Keep KSM off and verify `/sys/kernel/mm/ksm/run`; use fixed guest memory with no overcommit and no balloon unless host pressure or suspend tests show a concrete need. Hugepages are a performance experiment, not a security control.

High-isolation mode may turn SMT off or pin guest vCPU threads and QEMU emulator/IOThreads away from host-sensitive work, keeping SMT siblings in one domain where feasible. It must be benchmarked for scheduling, thermals, battery and suspend impact, and cannot claim side channels are eliminated. Nested virtualization stays off unless a required guest workload is explicitly reviewed. If a host-only virtio NIC is ever added, leave vhost-net off unless throughput measurements justify moving descriptor processing into the host kernel. Kernel capability may remain compiled.

## 18. Performance strategy

Compare **native host workload**, **current trusted-workstation VM**, and **new isolated work guest** on the same hardware, kernel, QEMU/libvirt version, power profile, thermal state and workload inputs. Record median, spread, host/guest configuration, battery state and regressions for CPU, compile, sequential disk, random IOPS, browser responsiveness, Wi-Fi throughput/latency, idle and active power, and suspend drain/resume success. Measure cold and warm starts where relevant. A compatibility NAT profile may be the current-VM comparator if that is what exists on the Linux host; document exact XML instead of assuming the Markdown example is deployed.

Prioritize KVM, EPT/VPID, virtio storage, efficient block I/O, direct Wi-Fi when feasible, and sufficient fixed RAM. Enable virgl, vhost, hugepages, pinning, or additional agents only after recording a material benefit and the extra host parser/device access. Define the acceptance threshold with the owner before using a benchmark to justify a persistent new channel. Do not claim a speed or battery improvement from design alone.

## 19. Recovery plan

Before any migration, retain the known signed audit11 and stock Ubuntu fallback entries and confirm a local-console boot path. Export the current VM XML, network XML, firewall/service/USBGuard state, routes, disk image metadata, and checked backup. Do not overwrite the only good guest disk. Use a new test overlay or separately named volume, then validate boot, guest login, network, workload, shutdown, suspend and rollback. A “clean base” must be verified before it becomes trusted; mere snapshot age does not make it clean.

After suspected guest compromise: disconnect/stop the guest, revoke guest account credentials from a clean environment, preserve evidence if needed, restore verified system state, examine persistent data as untrusted, and restore clean data from protected versioned backups. Recovery remains possible without mounting guest filesystems on the host desktop. Backup media and credentials are outside guest and QEMU writable reach. Test restore, low-space behavior, guest disk corruption, interrupted maintenance, Wi-Fi handoff failure, and actual fallback boot. The audit11 runbook's current fallback is recorded but its boot remains untested.

## 20. Residual risks and mode variants

Even with every target control passing, the guest can attack KVM, QEMU, SPICE/viewer, USB host/QEMU models, block and graphics parsers, host-kernel paths, firmware, and microarchitectural shared resources. Physical access, malicious peripherals, host administrator error, backup theft, supply-chain compromise, and guest credential theft remain. AppArmor and a networkless host reduce attack opportunities and blast radius; they do not make VM escape impossible.

The same two domains may expose two approved modes: **normal** (SMT on, audio output if required, approved graphics exception only) and **high isolation** (no optional graphics acceleration, mic or transfer channel; optional measured SMT/pinning policy). Both keep host networkless during guest operation and use the same single work guest. No permanent extra workload VM is introduced.

## 21. Validation matrix and implementation gate

Every future checker must distinguish `PASS`, `FAIL`, `WARN`, `UNKNOWN`, and `MANUAL_TEST_REQUIRED`. A value from this Windows document review is **UNKNOWN** unless the cited audit11 runbook specifically observed it; no missing Windows fixture is a Linux PASS. Negative tests must attempt the prohibited action from a root-compromised guest and record the result, not infer isolation from XML.

| Control or negative test | Evidence required on Linux host/guest | Current design-review state |
| --- | --- | --- |
| Host external routes, Wi-Fi association, DNS and listeners absent during guest operation | `ip -4/-6 route`, link/Wi-Fi state, resolver, `ss` and packet/reachability probes | UNKNOWN |
| Guest cannot reach host SSH, libvirt, DNS, desktop services or LAN paths | Guest-side probes on every configured interface/address family; host captures/firewall counters | UNKNOWN |
| Guest cannot access host home, MOK/recovery, management sockets, clipboard or shared filesystem | Live XML/device inventory, QEMU open files/LSM label, guest attempts and clipboard/file probes | UNKNOWN |
| No arbitrary USB attachment; approved MT7921U exclusively guest-owned | Host/guest USB trees, driver bindings, USBGuard, detach/replug/suspend tests | UNKNOWN; hardware/manual test required |
| Guest Internet and Wi-Fi after resume | Guest connectivity, throughput/latency, repeated suspend/resume, host route check | MANUAL_TEST_REQUIRED |
| QEMU unprivileged, AppArmor enforcing, seccomp and capabilities appropriate | UID/GID, `/proc`, AppArmor status/profile and denial log, helper process audit | UNKNOWN |
| No SPICE/VNC/libvirt TCP listener; required local display works | Live XML, QEMU args, host `ss`, guest UI/input test | UNKNOWN |
| KSM off, IOMMU active, nested virtualization off | sysfs/module state, `check-iommu.sh`, boot logs; do not infer from Kconfig | UNKNOWN |
| Guest system/data recovery and backup isolation | Restore drill, immutable base/backup permissions, full/low-space simulation | MANUAL_TEST_REQUIRED |
| Signed audit11/stock fallback remains bootable | Actual supervised boot and return; preserve runbook evidence | MANUAL_TEST_REQUIRED |
| CPU/disk/browser/network/power results | Repeatable native/current/new measurements and configuration record | UNKNOWN |

**Owner gate:** This document proposes no edits to libvirt, nftables, NetworkManager, USB binding, systemd, guest disks, host routing, GRUB, kernel config, or AppArmor. The owner must approve the architecture and the first implementation stage before those surfaces change. In particular, Wi-Fi assignment and host-network removal require direct ThinkPad validation and a recovery plan.

After approval, use independently reversible stages: (1) read-only host exposure auditor; (2) hardened work-domain XML in a separately named test guest/overlay; (3) remove clipboard/virtiofs/guest-agent runtime exposure; (4) networkless-host feasibility; (5) MT7921U guest ownership; (6) narrow USB/IP runtime; (7) maintenance transition and startup gate; (8) storage/snapshot redesign; (9) performance benchmarks; (10) supervised ThinkPad negative tests and recovery. Save current configuration and prove rollback at each stage before moving to the next. Update [VM threat models](VM_THREAT_MODELS.md), the [trusted profile](../vm-profiles/trusted-workstation/profile.md), [KVM guidance](KVM_SECURITY.md), [USB policy](USB_SECURITY.md), and [firewall guidance](FIREWALL.md) as those stages replace historical instructions; do not silently treat older examples as the new policy.
