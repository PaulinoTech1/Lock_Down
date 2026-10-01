# Audit13 stage-0 sustainable hardening review

**Status: REVIEW_REQUIRED — recommend no cut at this checkpoint.** This is a
Windows/offline review, not an audit13 effective config or a Linux-host test.
No fragment, build, signing, installation, boot, or host policy change is
authorized by this memo.

## Baseline and evidence state

- Baseline: `origin/main` commit `cf37b36066e6e21748c694cb4cbb4aba2f88a7f7`.
  The tracked resolved audit12 snapshot is
  [`config/candidate-6.18.53-lockdown-t14g3-audit12.config`](../../config/candidate-6.18.53-lockdown-t14g3-audit12.config),
  SHA-256 `444f72d745665f63acce59b7dce4fa9793140acbe56fd643deeb4aedf6dbc911`.
  Its local file hash matched the handoff. The [audit12 stage-1 record](../audit12/STAGE1.md)
  records the signed package SHA-256
  `3485262e37281c3b0b102fa62a86b2a95fbc694ada2f563225b0f59500544e35`
  and embedded image SHA-256
  `ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d`;
  those artifacts are absent here, so their hashes were **not** rechecked.
- **FACT — committed config:** `CONFIG_WATCHDOG=y`, `CONFIG_WATCHDOG_CORE=y`,
  `CONFIG_SOFT_WATCHDOG=y`, `CONFIG_LENOVO_SE10_WDT=y`,
  `CONFIG_LENOVO_SE30_WDT=y`, `CONFIG_WDAT_WDT=y`, `CONFIG_ITCO_WDT=y`, and
  `CONFIG_INTEL_MEI_WDT=y` in the resolved audit12 snapshot. These are observed
  snapshot values, not a fresh Kconfig resolution.
- **FACT — recorded Linux checkpoint:** The [owner runbook](../AUDIT12_OWNER_RUNBOOK.md)
  reports nonfatal legacy-driver probes, watchdog misc-device registration
  conflicts, and a possible legacy watchdog registration during a successful
  Secure Boot/integrity-lockdown boot. It does not identify the active watchdog
  owner or establish functional watchdog/crash recovery.
- **FACT — platform inventory:** [Hardware state](../HARDWARE.md) identifies a
  Lenovo ThinkPad T14 Gen 3 Intel, machine type `21AJ`, with an Alder Lake-U
  CPU. It does not record the live ACPI WDAT table or `/dev/watchdog*` binding.
- **OFFLINE_FIXTURE — source text:** The pinned `v6.18.53` stable-tree mirror's
  [watchdog Kconfig](https://github.com/gregkh/linux/blob/v6.18.53/drivers/watchdog/Kconfig),
  [SE10 driver](https://github.com/gregkh/linux/blob/v6.18.53/drivers/watchdog/lenovo_se10_wdt.c),
  and [SE30 driver](https://github.com/gregkh/linux/blob/v6.18.53/drivers/watchdog/lenovo_se30_wdt.c)
  were inspected as source text. The signed release archive, detached signature,
  reviewed keyring, and pinned signer are absent from this Windows checkout.
  Source authentication and effective-config resolution are **UNKNOWN**;
  mirror text is not a substitute for either.

The exact source-authentication state is `SOURCE_ANALYSIS=UNKNOWN` for this
Windows checkout. The previously recorded audit12 source archive digest is
`4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0`
and signer fingerprint is `647F28654894E3BD457199BE38DBBDC86092693E`,
but `linux-6.18.53.tar.xz`, its detached signature, and the reviewed public
keyring are absent at the paths named in the [stage-1 record](../audit12/STAGE1.md).
The signed audit12 package is absent too. No substitute archive was downloaded,
and neither `scripts/verify-kernel-source.sh` nor
`scripts/analyze-kconfig-delta.py` could be run with the required inputs.

## Discovery method and project constraints

The review compared the complete committed audit12 `.config` with
[`config/required-symbols.txt`](../../config/required-symbols.txt), the
[audit history](../kernel-audit-change-log.ms), [open issues](../../ISSUES.md),
[KVM guidance](../KVM_SECURITY.md), [USB policy](../USB_SECURITY.md), the
[two-domain phase](../TWO_DOMAIN_ENFORCEMENT_PHASE.md), and the existing VM
profiles. It searched enabled watchdog, framebuffer, FUSE, virtual networking,
test, fault-injection, and debug symbols. It treated config entries as compiled
capabilities, not evidence of binding or userspace use. The kernel is monolithic
(`CONFIG_MODULES` is disabled), so `lsmod` could not map these consumers.

The requested `docs/POWER_BASELINE.md` does not exist on this branch. Power
context was instead checked against [suspend](../SUSPEND.md),
[NVMe power](../NVME_POWER.md), and [display power](../DISPLAY_POWER.md).
The requested root-level `scripts/audit-config.sh` and
`scripts/validate-boot-critical.sh` live under
`lock-down-kernel/scripts/`. The analyzer invokes those paths along with
`scripts/preflight-check.sh` and `scripts/preflight-security.sh` after source
authentication and Kconfig resolution. Static gates on a proposed fragment
were not run because there is no authenticated source or approved proposal.

Audit12 itself changed `CONFIG_SAMPLES=y` to `n` with no non-sample effective
change beyond its release identity, per the [stage-1 record](../audit12/STAGE1.md).
It booted with Secure Boot integrity lockdown, mapper-backed ext4 root, and
zero failed units. Diskless KVM smoke passed twice; a disposable real guest
passed login, gateway/DNS, repository access, bounded write/hash, guest-agent,
and graceful shutdown checks. The owner reported speakers, USB storage and
Wi-Fi, microphone, HDMI, USB-C, touchpad, and TrackPoint working. One short
s2idle cycle resumed and Wi-Fi recovered. These are recorded Linux/owner
checkpoints, not checks repeated from Windows. Keyboard/hotkeys, brightness,
USB storage after reconnect, post-resume display/input/audio, crash dump,
watchdog behavior, actual stock fallback boot, and measured suspend drain
remain open. Stock Ubuntu remains the default; audit12 and audit11 remain
selectable recovery choices.

## Candidate comparison

Ratings describe the present evidence, not a prospective resolved config.
"Low" security benefit means that a reachable parser, device, or ioctl path
has not been shown on this machine; it is not a claim that compiled code is
harmless. Recovery complexity assumes the existing visible boot menu remains.

| Candidate | Reachability | Security benefit | Regression risk | Maintenance cost | Test cost | Recovery complexity | Confidence / classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SE10 + SE30 watchdog leaves | DMI-gated init; 21AJ absent from inspected mirror tables | Low until a live registration path is shown | Low to medium; watchdog conflicts and recovery behavior unresolved | Low if truly unmatched | Medium: binding, resolution, recovery | Low with audit12 retained | Medium on DMI mismatch; `UNKNOWN` pending source and host checks |
| `FB_HGA` | Audit12 record says an absent-HGA probe ran | Potentially removes one automatic legacy probe; parser/IO effect unquantified | Medium while LUKS/console fallback is not mapped | Low if irrelevant | Medium: boot and rescue console | Medium | Medium on probe, low on closure; `UNKNOWN` |
| `FB_UVESA` | Audit12 record says its `v86d` helper was missing | Potentially removes an automatic legacy probe/helper request | Medium for early display/recovery | Low if no consumer | High: prompt and fallback visibility | Medium | Medium on probe, low on closure; `UNKNOWN` |
| `FUSE_DAX` | Depends on virtiofs/DAX path; actual mounts unknown | Unknown until guest/host virtiofs use is mapped | Medium for shared-memory VM workflows | High if daily workflow requires it | High: mounts and workloads | Medium | Low; `UNKNOWN` |
| `FUSE_PASSTHROUGH` | FUSE userspace requests may invoke it; actual use unknown | Unknown until passthrough users are mapped | Medium for desktop/filesystem consumers | High if routine use exists | High: filesystem workloads | Medium | Low; `UNKNOWN` |
| `FUSE_IO_URING` | FUSE request transport; actual use unknown | Unknown until mount and server options are mapped | Medium for filesystem performance | High if routine use exists | High: filesystem workloads | Medium | Low; `UNKNOWN` |
| `VHOST_NET` | Guest-influenced descriptors can reach host kernel if explicitly enabled | Potentially meaningful when enabled; no current use proven | Medium for trusted/lab guest performance | Medium if workflows change | Medium: every VM profile and throughput | Medium | Medium on mechanism, low on runtime use; `UNKNOWN` |
| `TUN`, `BRIDGE`, `VIRTIO_NET`, `MACVLAN`, `MACVTAP` | Libvirt/NAT and test guests use virtual networking; future work guest differs | Removal could narrow kernel network paths, but active/recovery use is documented | High | High: likely rebuilds or exceptions | High: current and future guests | High | High on workflow conflict; `NOT_JUSTIFIED` now |
| Remaining enabled debug leaves | `DEBUG_MISC` and `DEBUG_VFS` are enabled; exposure differs by symbol | Unknown without exact definition and interface mapping | Medium during open crash/boot diagnostics | Medium | Medium | Medium | Low; `UNKNOWN` |

### Why the ratings differ

**CONFIRMED from the repository:** `FB_HGA=y` and `FB_UVESA=y`; the
[audit log](../kernel-audit-change-log.ms) records HGA hardware absent and
`uvesafb` failing to find `v86d` during the audit12 first boot. The record is
a summary, not the raw timestamped journal, so exact probe order, callers,
error codes, and all other failing drivers remain **UNKNOWN**. The enabled
`FB_EFI`, `FRAMEBUFFER_CONSOLE`, `DRM_SIMPLEDRM`, and `DRM_I915` paths are
distinct and must be preserved. `FB_EFI` is explicitly required for the
boot console by the project's required-symbol file. **HIGH-CONFIDENCE
INFERENCE:** removing an irrelevant legacy framebuffer leaf could stop its
automatic probe; whether either probe creates a reachable security boundary
or affects recovery is still **UNKNOWN**. Do not infer an idle-power benefit.

**CONFIRMED from the repository:** `FUSE_FS`, `FUSE_DAX`, `FUSE_PASSTHROUGH`,
and `FUSE_IO_URING` are enabled. The [prior stage-0 review](../audit12/STAGE0_REVIEW.md)
records mirror Kconfig clauses: DAX depends on virtiofs/FS_DAX/DAX;
passthrough depends on core FUSE and selects FS_STACK; FUSE io_uring depends
on core FUSE and io_uring. The historical trusted-workstation profile names
virtiofs, while the proposed production work-domain XML forbids shared
filesystems. That proposal is not live-consumer proof. **HYPOTHESIS:** an
optional leaf might be removable after desktop, container, VM, and recovery
use is inventoried. Core FUSE/AutoFS remain preserved.

**CONFIRMED from the repository:** `VHOST_NET`, `TUN`, `BRIDGE`, `VIRTIO_NET`,
`MACVLAN`, and `MACVTAP` are enabled. [KVM guidance](../KVM_SECURITY.md)
states that vhost can put guest-influenced virtio packet/descriptor processing
inside the host kernel and is off by policy for untrusted guests, optional for
trusted ones. The audit12 disposable guest used libvirt NAT and virtio
networking. Legacy trusted/lab profiles and the evidence collector also
expect virtual networking; the two-domain work-guest profile is a separate
future path. **HIGH-CONFIDENCE INFERENCE:** removing TUN/bridge/virtio-net
now would create routine validation or recovery friction. **UNKNOWN:**
whether any current domain opens `/dev/vhost-net`, which other userspace
consumers use MACVLAN/MACVTAP, and whether future trusted guests need vhost
throughput. A `VHOST_NET` cut is deferred, not bundled with watchdogs.

**CONFIRMED from the snapshot:** `SAMPLES`, `KUNIT`, `FAULT_INJECTION`,
`TEST_POWER`, and the listed `TEST_*` facilities are disabled. Audit11 removed
`TEST_POWER`, `IO_URING_MOCK_FILE`, and
`THINKPAD_ACPI_DEBUGFACILITIES`; audit12 removed `SAMPLES`. Remaining
`DEBUG_MISC`, `DEBUG_VFS`, `DEBUG_KERNEL`, and `DEBUG_WX` are enabled, while
`DEBUG_FS` is disabled. The project's
[forbidden-config guidance](../../lock-down-kernel/references/forbidden-config.md)
explains that `DEBUG_KERNEL=y` is an `EXPERT`-selected umbrella here and that
turning off `EXPERT` would lower the retained mmap ASLR defaults. Preserve
`DEBUG_KERNEL`, `DEBUG_WX`, and the existing ASLR settings. The specific
semantics and reachable interfaces of `DEBUG_MISC` and `DEBUG_VFS` were not
authenticated here. **HYPOTHESIS:** a narrowly scoped leaf might be removable
later, but disabling useful diagnostics before crash-dump and recovery
validation could increase maintenance burden.

The [threat model](../THREAT_MODEL.md) treats VM escape, malicious USB, and
firmware as relevant boundaries. The only network adapter is USB and the
owner requires USB/IP for the guest workflow; this makes broad USB or guest
cuts particularly costly. The [KVM security record](../KVM_SECURITY.md) and
[two-domain phase](../TWO_DOMAIN_ENFORCEMENT_PHASE.md) describe policies that
still need live enforcement. No kernel cut is credited for those userspace
controls or for an unmeasured battery-life change.

### Reachability channels

Every row above is compiled (`=y`); what can actually invoke it differs:

| Candidate | Boot/probe and firmware/hardware trigger | Userspace, guest, device-node, parser or ioctl route |
| --- | --- | --- |
| SE10/SE30 | Mirror source shows DMI check at init before platform registration; recorded 21AJ is unmatched. A different/spoofed DMI identity is a theoretical firmware-controlled route, not observed here. | A matching platform could register a watchdog device. No SE10/SE30 node or owner is evidenced on this host; guest and unprivileged reachability are **UNKNOWN**. |
| HGA/UVESA | Audit12 summary records both legacy probes; exact init path and source dependencies are **UNKNOWN**. | UVESA requests a missing `v86d` helper; exact userspace entry, framebuffer node, ioctl exposure, and permission state are **UNKNOWN**. No guest trigger is recorded. |
| FUSE optional leaves | No boot probe, external-hardware trigger, or firmware invocation is evidenced. | Core FUSE is a userspace filesystem interface; per-leaf request, passthrough, and virtiofs/guest reachability are **UNKNOWN** until mounts and workload options are inventoried. |
| VHOST_NET | No automatic probe or external hardware trigger is established. | KVM guidance describes guest-influenced descriptor processing in host kernel when QEMU opts in; `/dev/vhost-net` use on audit12 is **UNKNOWN**. |
| Virtual networking set | No hardware or firmware binding is needed for virtual NICs. | Libvirt NAT/virtio guest execution is recorded. Bridge, TUN, MACVLAN/MACVTAP, packet parsers, and ioctls have differing call paths; exact current consumers beyond the known guest are **UNKNOWN**. |
| Debug leaves | No device or firmware trigger is established. | A reachable debug interface from `DEBUG_MISC` or `DEBUG_VFS` is **UNKNOWN**; `DEBUG_FS` is disabled. Do not infer an exposed debugger from an enabled umbrella symbol. |

This mapping is intentionally incomplete where live inventories, raw logs, or
authenticated source are missing. It prevents a compiled-but-DMI-gated
watchdog leaf from being valued above a demonstrated boot probe merely by
counting symbols. It also prevents a noisy probe from being called a security
vulnerability without a reachable input and effect.

## Two bounded choices

| Choice | Evidence and possible effect | Decision |
| --- | --- | --- |
| Retain the audit12 watchdog profile | Preserves every current recovery path while the live owner, ACPI WDAT presence, and conflict cause remain unknown. It carries built-in SE10/SE30 code whose DMI paths appear inapplicable to this machine. | **Recommend now.** No claimed security or power improvement. |
| Propose `CONFIG_LENOVO_SE10_WDT=n` and `CONFIG_LENOVO_SE30_WDT=n` only | Both are leaf driver assignments with model-gated initialization. Removing them might reduce compiled code and an unused probe path. The DMI mismatch makes a direct 21AJ binding unlikely; it also makes any practical exposure reduction small and unproven. | Defer until authenticated Kconfig resolution and Linux binding evidence. This is the sole potential cut set considered, not an approved change. |

For each proposed leaf, the observed value and source relations are:

| Symbol | Observed value | Pinned source definition and binding | Reachable interface / plausible security effect |
| --- | --- | --- | --- |
| `LENOVO_SE10_WDT` | `y` | Tristate; `depends on (X86 && DMI) || COMPILE_TEST` and `HAS_IOPORT`; `select WATCHDOG_CORE`. Its source calls `dmi_check_system` before registering its platform driver. Listed DMI product names are `12NH`–`12NM`, `13LJ`–`13LK`, and `13S1`–`13S6`, none `21AJ`. | On a matching machine, registers a watchdog device through the watchdog core and touches platform I/O. On this recorded 21AJ, reaching that path is **inferred unlikely**, not live-proven absent. Disabling might remove code; no vulnerability or measurable reduction is established. |
| `LENOVO_SE30_WDT` | `y` | Same direct dependencies and `WATCHDOG_CORE` selection. Its init checks DMI before driver registration; listed products are `11NA`–`11NC` and `11NH`–`11NK`, none `21AJ`. | Same bounded inference. The runbook's misc-device conflict is **not** attributed to this driver by the available evidence. |

The selected `WATCHDOG_CORE` is already `y` and is needed by other enabled
drivers; turning either Lenovo leaf off must not be assumed to remove the
core. Direct Kconfig clauses and driver DMI tables were inspected, but a
whole-tree reverse-selector search against authenticated 6.18.53 source and a
full dependency/collateral analysis were not performed. Their results are
**UNKNOWN**. The Linux analyzer must resolve any approved proposal from the
exact audit12 snapshot and report every effective change before a fragment is
accepted. A plain text diff of assignments does not establish closure.

For the two-leaf idea, the **hypothetical request** is
`LENOVO_SE10_WDT=y→n` and `LENOVO_SE30_WDT=y→n`. Its resolved changes,
collateral changes, rejected assignments, required-symbol results, and
policy-gate results are each **UNKNOWN** because no authenticated-source
analysis was run. For framebuffer, FUSE, vhost, and debug candidates, even
the full source dependencies and reverse selectors are **UNKNOWN**. Their
config entries are discovery evidence only, not accepted proposals.

`SOFT_WATCHDOG` is a software fallback, while `WDAT_WDT` depends on ACPI and
selects `ACPI_WATCHDOG`; the latter's help says it can take over native iTCO
on systems with a WDAT table. `ITCO_WDT` depends on x86, PCI, and I/O-port
support and selects Intel platform dependencies under its Kconfig conditions.
Those paths, watchdog core, and `INTEL_MEI_WDT` stay intact in either choice.
The journal's registration conflicts alone do not identify which driver is
active or justify disabling a hardware recovery path.

## Risk, planned checks, and rollback

| Item | Risk / unresolved evidence | Required check before a cut | Rollback |
| --- | --- | --- | --- |
| SE10/SE30 pair | Unexpected selector/collateral change, or undocumented use on this host. Security gain is unmeasured. | Authenticate the 6.18.53 source; inspect reverse relations; run the repository Kconfig delta analyzer against the exact audit12 config; require only the two approved leaf changes or explicitly review every collateral change. On Linux, record DMI identity, loaded/registered watchdog drivers, `/sys/class/watchdog/`, `/dev/watchdog*`, ACPI WDAT presence, journal conflict context, and any watchdog service ownership without opening/arming the device. | Revert the two assignments and re-resolve from the audit12 snapshot; retain the signed audit12, audit11, and stock Ubuntu recovery entries. |
| Active watchdog/recovery | Removing the real owner could affect recovery, suspend, or crash diagnostics. Audit12 watchdog and crash behavior is not functionally tested. | If a later candidate is approved, keep core/Intel/ACPI paths and run supervised watchdog, crash-dump, suspend/resume, encrypted-root, real-guest, hardware, and actual fallback checks before promotion. | Select retained signed audit12 or stock Ubuntu from the visible boot menu; do not make audit13 default until recovery is demonstrated. |

No check in this table was run against the ThinkPad in this Windows stage.
The audit12 short s2idle cycle and real-guest exercise in the
[stage-1 record](../audit12/STAGE1.md) support only their documented scope.
Post-resume display/input/audio, keyboard/brightness, USB data persistence
after reconnect, crash behavior, stock-kernel fallback boot, and measured
suspend drain remain open. A smaller image would establish neither security
nor power benefit.

If the owner later approves the SE10/SE30 pair after the missing evidence is
collected, its candidate-specific validation sequence is:

| Gate | Required observation |
| --- | --- |
| Static | Authenticate Linux 6.18.53 using the recorded archive SHA-256, detached signature, reviewed keyring, and pinned signer. Resolve an exact two-symbol proposal from the audit12 effective config with `scripts/analyze-kconfig-delta.py`. Review requested, resolved, collateral and rejected assignments, source dependency/reverse-selector report, required-symbol checks, and every policy gate before creating any candidate config. |
| Boot and log comparison | Keep stock Ubuntu as GRUB default and manually select a uniquely named candidate. Confirm Secure Boot/integrity lockdown, LUKS/ext4 root, 12 CPUs, zero failed units, and compare watchdog/device registration plus legacy-probe journal lines to audit12. An absent warning alone is not a security pass. |
| Hardware | Recheck the sole MT7921U network path, USB storage including reconnect, internal/external displays, keyboard/brightness, touchpad/TrackPoint, audio, USB-C/HDMI, and watchdog owner/firmware table without arming a watchdog merely to inspect it. |
| VM | Re-run the diskless KVM smoke and the disposable real-guest login, network, bounded workload, agent, and graceful-shutdown path; keep required USB/IP and host/guest separation workflows intact. |
| Suspend | Supervise repeated s2idle cycles with Wi-Fi reassociation, display, input, audio, storage, and error-journal checks. Measure drain separately under matched conditions before any power claim. |
| Recovery | Preserve signed audit12 and audit11 plus stock Ubuntu and the visible menu. Demonstrate a real stock fallback boot and manual return before promotion. Watchdog reset or destructive crash experiments require a separate owner decision and recovery preparation. |

For `FB_HGA` or `FB_UVESA`, the extra gate is LUKS prompt, early console,
recovery-shell, graphics handoff, and stock-fallback visibility with a raw
journal comparison; for FUSE, it is a mapped desktop/container/virtiofs
workload; for vhost and other networking, it is every current and planned VM
profile plus throughput and recovery checks. These are **deferred test
requirements**, not tests performed or approval to combine cut sets.

## Recommendation and stop gate

**Recommend no audit13 kernel cut now.** The SE10/SE30 DMI mismatch is
useful narrowing evidence, but it does not resolve the live conflict or
justify changing a running daily-driver kernel. Obtain read-only Linux binding
evidence and authenticated-source resolution first. The owner can then decide
whether the two-leaf set is worth a separate, supervised build experiment.

Leaving audit12 unchanged is currently **safer and more sustainable** than
applying the hypothetical SE10/SE30 cut: its regression and investigation
cost is real, while no exposed 21AJ driver path or concrete security benefit
has been established. The strongest alternative lead is the recorded legacy
framebuffer probe noise, but the raw journal, authenticated source closure,
and early-console dependency evidence are missing. It is deferred rather
than bundled with watchdogs. FUSE leaves, vhost, virtual networking, and
debug facilities are deferred for the distinct consumer and recovery reasons
above.

Optional FUSE leaves are a separate later review. Preserve core FUSE/AutoFS,
KVM, VFIO/IOMMU, crash diagnostics, Intel graphics and SOF audio, the sole
MT7921U network path and USB storage, direct USB-C/HDMI, encrypted boot,
Snap/SquashFS, and the owner-required USB/IP core/VHCI/host paths. Do not
silently change BPF, namespaces, io_uring core, or guest integration.

**Owner gate:** Review this memo. No audit13 fragment or build begins unless
the owner explicitly approves a specific cut set after Linux-side binding
evidence and a complete resolved collateral delta are available.
