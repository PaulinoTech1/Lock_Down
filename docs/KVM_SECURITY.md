# KVM Security

Target hardware: Lenovo ThinkPad T14 Gen 3 Intel (MT 21AJ), i5-1245U
(Alder Lake-U, 2P+8E). VT-x/EPT/VPID and VT-d with interrupt remapping are
present in silicon (VERIFIED from inventory; UEFI toggle state and active
kernel enforcement REQUIRE runtime verification with
`scripts/check-iommu.sh`).

Scope: this document covers host-side KVM hardening on this machine only.
Guest selection, per-profile policies, and what each profile does NOT
protect against live in `VM_THREAT_MODELS.md`.

## Hardware virtualization primitives

### VT-x, EPT, VPID

- Purpose: VT-x provides hardware CPU virtualization (VMX root/non-root
  mode). EPT (Extended Page Tables) gives the guest a second-level address
  translation so the host does not have to shadow page tables in software.
  VPID (Virtual Processor IDs) tags TLB entries per VM so entries do not
  have to be flushed on every VM entry/exit.
- Why it matters: EPT removes a large class of software page-table-shadowing
  bugs from the trusted path, and VPID reduces the performance cost of
  isolation. Both are standard on this CPU; no configuration is needed
  beyond loading `kvm_intel`.
- Cost: near zero. These are passive hardware features.
- Limitation: they isolate memory translation, not microarchitectural
  state. Speculative-execution and cross-thread side channels still apply
  (see `CPU_SECURITY.md` and the SMT policy note below).
- Recovery path: none needed; if `kvm_intel` fails to load, check the UEFI
  virtualization toggle and dmesg.

### VT-d + interrupt remapping

- Purpose: VT-d gives devices a remapped view of memory (DMA remapping), so
  a device can only DMA into memory it has been granted. Interrupt
  remapping validates MSI/MSI-X interrupt sources so a device cannot inject
  interrupts that belong to another device or vector an attack at the host.
- Required kernel state: `intel_iommu=on` (or `iommu=pt` plus explicit
  enablement for assigned devices), and interrupt remapping active. Verify
  with `scripts/check-iommu.sh`; do not assume DMA isolation merely because
  the IOMMU exists.
- Why it matters here: Thunderbolt 4 ports and USB devices are DMA-capable.
  With Thunderbolt disabled in UEFI (project baseline), the remaining
  DMA-capable surface is USB. VT-d is also the prerequisite for any future
  PCI passthrough decision.
- Cost: small IOTLB overhead on DMA-heavy workloads; negligible for normal
  VM use.
- Limitation: IOMMU groups must actually isolate the devices in question. If
  two devices share an IOMMU group, assigning one to a guest exposes the
  other. `scripts/check-iommu.sh` lists groups and flags weak isolation.
- Recovery path: if the IOMMU is not active after enabling, the host still
  runs VMs, but untrusted profiles must be treated as UNVERIFIED until
  `check-iommu.sh` passes. Do not run the untrusted-analysis profile without
  VT-d confirmed active.

### KVM Intel module options

Default posture (RECOMMENDED):

```text
# /etc/modprobe.d/kvm-intel.conf
options kvm_intel nested=0
options kvm_intel enable_apicv=1
```

- `nested=0`: nested virtualization off. Purpose: reduces the attack surface
  of the VMX implementation exposed to guests (L1 hypervisor bugs are out of
  scope for this workstation). Cost: guests cannot run their own hypervisors.
  Limitation: none for the defined profiles. Recovery: remove the line and
  reload the module if a legitimate nested use case appears.
- `enable_apicv=1`: APIC virtualization on. Purpose: performance (fewer
  exits); no known security downside on current microcode. Confidence: High.

### QEMU and libvirt

- Run VMs through libvirt (`virt-manager` / `virsh`), not raw `qemu`
  command lines. Purpose: libvirt applies sVirt labeling, cgroup placement,
  and seccomp filtering consistently. Cost: slightly less flexibility than
  hand-rolled QEMU. Limitation: libvirt defaults are distribution
  defaults; they must be tightened per profile (see `vm-profiles/`).
- QEMU must run as an unprivileged user (`qemu:///system` with the
  `libvirt-qemu` user), never as root. Purpose: a VM escape lands in an
  unprivileged account, not uid 0. Cost: none. Limitation: an escape still
  lands on the host; this is containment depth, not prevention.
- Keep QEMU and libvirt patched via Ubuntu security updates. An unpatched
  hypervisor is the most likely VM-escape path on this machine.
  Confidence: High.

### sVirt / AppArmor confinement

- Purpose: sVirt applies per-VM AppArmor (or SELinux) labels so that each
  QEMU process can only touch its own disk images, sockets, and resources.
  A compromised guest process cannot read another VM's disk image even if
  filesystem permissions would otherwise allow it.
- Configuration: libvirt's AppArmor driver must be active
  (`security_driver = "apparmor"` in `/etc/libvirt/qemu.conf`).
  Per-profile XML shows explicit `<seclabel>` usage; the default dynamic
  labeling is acceptable for trusted profiles but the untrusted profile
  pins its label.
- Cost: near zero at runtime; debugging denials requires reading the audit
  log.
- Limitation: sVirt confines the QEMU process, not the guest kernel. A
  guest-kernel-to-host-kernel escape (KVM bug) is outside sVirt's reach.
  AppArmor must itself be in enforce mode; a permissive or disabled
  AppArmor silently voids this control. Verify with `aa-status`.
- Recovery path: if a VM fails to start with AppArmor denials, read the
  denial, fix the labeling or path, and re-test. Do not set the profile to
  complain mode as a permanent fix.

### KSM (Kernel Same-page Merging)

- Default: KSM stays OFF, and it is explicitly disabled for hostile guests.
- Purpose of KSM: deduplicates identical memory pages across VMs to save
  RAM.
- Why it is off here: memory deduplication is a measurable side channel.
  A guest can probe whether a page it writes already exists elsewhere on
  the host (via timing of the merge/copy-on-write), leaking information
  about host or co-resident guest memory contents. This is a documented,
  practical attack class, not a theoretical one.
- Cost of disabling: higher memory use when running several similar VMs.
  On a 16/32 GB laptop this is a real cost; size the network-lab profile
  accordingly.
- Limitation: disabling KSM removes only the dedup channel. Other
  microarchitectural channels (cache timing, etc.) remain.
- Setting: ensure `ksmtuned` is not installed or is stopped, and
  `/sys/kernel/mm/ksm/run` reads `0`. The untrusted-analysis profile
  documents this as a precondition.

### vhost acceleration

- What it is: vhost-net (and vhost-user variants) move virtio packet/IO
  processing out of the QEMU userspace process and into the host kernel
  (vhost-net) or a dedicated userspace backend (vhost-user).
- Tradeoff: vhost-net improves throughput and lowers latency, but it puts
  guest-influenced virtio descriptor processing inside the host kernel. A
  bug in that path is a guest-to-host-kernel path with no QEMU process
  boundary in between.
- Default for this project: vhost acceleration is OFF for untrusted guests
  (use emulated virtio-net through QEMU userspace). OPTIONAL for trusted
  guests where the performance matters and the guest is not hostile.
- Cost of leaving it off: measurably lower network throughput for the VM;
  irrelevant for an analysis VM that is mostly idle or on an isolated NAT.
- Limitation: turning vhost off does not remove the virtio attack surface
  entirely; it only keeps the parsing in userspace QEMU under sVirt
  confinement.
- How to set: in the domain XML, use `<model type='virtio'/>` without
  vhost driver elements for untrusted guests. For trusted guests where it
  is wanted, add `<driver name='vhost'/>` on the interface explicitly so
  the choice is visible.

### nftables VM zones

- Purpose: every VM network defined in libvirt gets a corresponding
  nftables zone so that guest traffic is filtered at the host boundary,
  independent of libvirt's own iptables/nftables rules.
- Zones:
  - `trusted`: NAT to the upstream (USB Wi-Fi) with stateful return
    traffic allowed; no inbound initiation from the WAN side.
  - `untrusted`: isolated NAT with NO route to the host's LAN-side
    addresses and no forwarding to other zones; DNS only via the host
    resolver if the profile needs it, otherwise no DNS (documented per
    profile).
  - `lab-*`: per-segment zones for the network-lab profile with explicit
    inter-zone rules (default deny between lab segments).
- Why nftables instead of relying on libvirt's default network filters:
  libvirt's default NAT network is permissive by design and shared across
  all VMs on it. Per-profile zones make the isolation explicit and
  auditable.
- Cost: one-time rule authoring; ongoing cost is reading the ruleset when
  debugging connectivity.
- Limitation: nftables filters packets; it does not inspect guest intent.
  A hostile guest on an isolated NAT can still attack whatever the NAT
  exposes (e.g., a host DNS resolver if one is offered). Keep the exposed
  services minimal per profile.
- Recovery path: rules live in versioned files under the repo; reloading
  is `nft -f`. A bad rule that kills host networking is recovered by
  flushing from the local console (`nft flush ruleset` restores an empty
  table; host networking via NetworkManager does not depend on these
  tables).

## Defaults summary

- VM model favors isolation over integration: separate disk images, no
  shared host filesystem, sVirt confinement on, KSM off, vhost off for
  untrusted guests, per-profile nftables zones.
- Anything that weakens isolation (clipboard sharing, USB redirection,
  filesystem passthrough, PCI passthrough) is opt-in per profile and must
  carry a written justification in the profile file.

## Confidence notes

- VT-x/EPT/VPID, VT-d + IRQ remapping present: VERIFIED from inventory
  (capability). Active enforcement: UNVERIFIED until `check-iommu.sh`
  passes on the machine.
- KSM side-channel risk: VERIFIED (documented attack class). Confidence:
  High.
- vhost-in-kernel tradeoff: RECOMMENDED analysis. Confidence: High that the
  boundary change is real; Medium on exploitability of any specific
  vhost-net bug at a given patch level.
