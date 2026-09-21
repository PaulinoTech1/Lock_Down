# VM Threat Models

Three profiles for KVM/libvirt use on this workstation. Each profile names
its assumed adversary, what it protects, what it costs, and what it does
NOT protect against. Concrete libvirt configurations live in
`../vm-profiles/<name>/profile.md`. Host-side hardening (VT-d, sVirt,
nftables zones, KSM, vhost) is documented in `KVM_SECURITY.md`.

No profile protects against a VM escape (host kernel or QEMU
vulnerability), against microarchitectural side channels shared with the
host (cache timing, cross-thread speculation), or against firmware-level
compromise. Those are stated per profile below, not buried.

## Profile 1: trusted-workstation (daily driver VM)

- Assumed adversary: ordinary internet threats (malicious websites,
  phishing payloads, drive-by downloads) plus commodity malware the user
  might encounter in daily use. The guest OS and its applications are
  assumed non-hostile; the user deliberately runs software inside it.
- What it protects: isolates daily browsing/work from the host OS so that
  commodity malware that compromises the guest does not automatically reach
  host files, host credentials, or host network identity. Snapshot/rollback
  gives a clean recovery path from guest compromise.
- Integration allowed: shared clipboard (one direction or both, user
  choice), a shared folder for moving files in/out (mounted explicitly, not
  the whole home directory), USB redirection for specific devices the user
  approves per session. Each integration is a hole in the boundary and is
  documented as such in the profile.
- Tradeoffs and cost: convenience integrations widen the guest-to-host
  channel. Clipboard sharing lets a compromised guest read host clipboard
  contents (passwords copied on the host). A shared folder lets guest
  malware write files the host user will later open. USB redirection
  exposes the raw device to the guest.
- What it does NOT protect against:
  - VM escape: a QEMU or KVM bug still reaches the host. The profile does
    not claim otherwise.
  - Microarchitectural side channels: the guest shares physical cores with
    the host; cache-timing and speculative-execution channels are not
    closed by this profile.
  - Malicious use of the allowed integrations: if the guest is actually
    hostile, the clipboard and shared folder are exfiltration paths.
  - Host compromise through the shared folder: files moved from guest to
    host must still be treated as untrusted on the host.
- Label: RECOMMENDED as the default daily-use posture. Confidence: High
  that it raises the bar against commodity threats; Medium that any given
  user will keep the integrations minimal in practice.

## Profile 2: untrusted-analysis (malware-ish / suspicious software)

- Assumed adversary: the guest is assumed HOSTILE. It may run malware,
  actively attempt VM detection and escape, probe virtual devices for bugs,
  and attempt network reconnaissance. The analyst's safety depends on the
  boundary holding.
- What it protects: containment of a hostile guest. No shared host
  filesystem, no clipboard, no drag-and-drop, no automatic USB redirection,
  no 9p, no virtiofs, no PCI passthrough. The guest gets an isolated NAT
  network with no route to the host LAN and no forwarding to other zones.
  sVirt labeling pins the QEMU process to its own resources. Disk images
  are separate per analysis target and created fresh per run.
- What is explicitly forbidden and why:
  - Host filesystem passthrough (9p/virtiofs/host mounts): a hostile
    guest with write access to host paths is no longer contained.
  - Clipboard / drag-and-drop: exfiltration and host-input injection
    channels.
  - Automatic USB redirection: a hostile guest should not get raw access
    to host USB devices; the external Wi-Fi adapter is the host's only
    network path and must never be redirected.
  - PCI passthrough: gives the guest DMA-capable hardware; on a laptop
    with shared IOMMU groups this is both risky and likely broken. Not
    justified for analysis.
- Network posture: isolated NAT zone (`untrusted`), no inbound from WAN,
  no guest-to-host-LAN traffic, DNS only if the analysis needs it and only
  via a resolver that logs queries. All guest traffic is untrusted; the
  host firewall treats the zone as hostile.
- KSM: off (precondition). vhost: off (virtio through QEMU userspace).
  SMT: optionally disabled while hostile VMs run (see `CPU_SECURITY.md`;
  OPTIONAL with cost).
- Tradeoffs and cost: getting samples and logs in/out is deliberately
  awkward (fresh disk images, no shared folders). Analysis throughput is
  lower than a permissive lab. The isolated network means samples that
  need real internet behavior need an explicit, logged exception.
- What it does NOT protect against:
  - VM escape: a KVM/QEMU zero-day still escapes. This profile reduces the
    value of an escape (sVirt, unprivileged QEMU user) but does not prevent
    it.
  - Microarchitectural side channels shared with the host: cache timing,
    port contention, and (if SMT is left on) cross-thread speculation
    channels remain. Disabling SMT narrows but does not close this class.
  - VM detection and evasion: malware that refuses to run under
    virtualization is an analysis limitation, not a safety failure, but it
    is out of scope for this profile to defeat.
  - Firmware/BIOS-level persistence by the sample: out of scope; the
    threat model assumes the sample runs inside the guest.
- Label: RECOMMENDED for any suspicious-software work. Confidence: High
  that the listed prohibitions are the correct set; Medium on the residual
  escape risk at any given patch level (depends on QEMU/KVM patch state).

## Profile 3: network-lab (multiple VMs, inter-VM segmentation)

- Assumed adversary: varies per VM; the lab exists to observe traffic
  between systems that do not trust each other (e.g., attacker VM,
  victim VM, router/firewall VM). At least one VM is treated as hostile to
  the others.
- What it protects: segmentation between lab VMs. Each lab segment is its
  own libvirt network with its own nftables zone; inter-zone forwarding
  defaults to deny and is opened only with explicit rules that document
  which traffic is expected (e.g., victim may initiate to router; attacker
  may initiate to victim on specified ports). No lab VM gets host
  filesystem access. sVirt keeps QEMU processes mutually confined.
- Design: a router VM (or host-side nftables, preferred) enforces the
  segmentation so the policy is visible in one place. Host-side nftables is
  preferred over a router VM because a compromised router VM would then own
  the segmentation.
- Tradeoffs and cost: more networks and rules to author and maintain; each
  new lab scenario needs its rule set reviewed. KSM stays off, so memory
  use scales linearly with VM count on a laptop; keep the lab small (2-4
  VMs) or accept swapping.
- What it does NOT protect against:
  - VM escape: same residual as the other profiles.
  - Side channels between co-resident lab VMs and the host: same
    microarchitectural exposure; lab VMs share physical cores with each
    other and with the host.
  - Misconfiguration: the segmentation is only as good as the nftables
    rules. Every inter-zone allow rule is a deliberate hole; review them
    like firewall rules, because they are firewall rules.
  - A hostile lab VM attacking the virtual network infrastructure itself
    (e.g., ARP spoofing inside its own segment): expected lab behavior,
    contained by segmentation, not prevented.
- Label: RECOMMENDED for structured lab work. Confidence: High on the
  segmentation model; Medium on operators keeping rule sets minimal over
  time (rule sprawl is the observed failure mode).

## Cross-profile rules

- No profile gets PCI passthrough by default. Justification required, in
  writing, in the profile file, plus a `check-iommu.sh` pass showing the
  device is in an isolated IOMMU group.
- No profile disables AppArmor/sVirt. If a VM will not start under
  confinement, the profile is fixed; confinement is not.
- Snapshots before running anything untrusted. Snapshot storage must have
  free space verified first; a snapshot that fails midway is worse than no
  snapshot because it looks like protection.
- Host patching (QEMU, libvirt, kernel) is part of every profile's safety.
  An unpatched hypervisor voids the assumptions above.

## What no VM profile protects against (restated once, applies to all)

1. VM escape via hypervisor or host-kernel vulnerability.
2. Microarchitectural side channels (cache, speculation, cross-thread)
   shared between guest and host or between co-resident guests.
3. Firmware-level compromise (UEFI, ME, device firmware).
4. Physical access / evil maid.
5. The user deliberately weakening the profile (enabling passthrough,
   shared folders, or bridged networking "temporarily" and forgetting).
