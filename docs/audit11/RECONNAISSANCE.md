# Audit11 read-only reconnaissance and research backlog

Date: 2026-09-29. Scope: secondary engineering review of the single T14 Gen 3
Intel 21AJ. No kernel implementation is authorized by this report.

Delivery note: the owner subsequently requested a `windows-codex` branch and
commit of this report. The branch, clean/dirty state, and no-commit statements
below record the reconnaissance checkpoint before that delivery request.

The safest useful work is to strengthen source/artifact provenance, make static
gates cover the current configuration, and reconcile current-status claims in
separate documentation proposals. These improvements can be prepared without
altering audit10 evidence. Driver reductions are conditional research proposals,
not a deployable configuration. Audit10 remains a LIVE ACTIVE CANDIDATE UNDER
VALIDATION.

## Environment, isolation, and method

- Repository: https://github.com/PaulinoTech1/Lock_Down
- HEAD: `4dfd9e150667393ddf1f2c3688a11a75ba0387c1`.
- Latest commit: `Record audit10 install boot USB and KVM smoke evidence`.
- Branch: `research/audit11-kconfig-review`.
- Worktree: `E:\speedzone_MS\LOCK_DOWN`, a fresh independent clone, not the
  owner's Linux build tree. This is a research branch in the clone's primary
  worktree, not a linked worktree. No work was written on main.
- Initial status: clean. Final intended change: this uncommitted research report
  only. HEAD exactly matches the handoff; there are no subsequent commits to
  reconcile.
- Windows PowerShell, Git, Python, and Git Bash are available. Restricted network
  cloning and Git Bash process creation initially failed; approved sandbox
  escalation permitted the clone, branch creation, and static checks. No host
  software was installed. WSL enumeration returned access denied; Linux source
  resolution capability was not established. No complete Linux source tree was
  present in the checkout.
- Skills actually used: plugin-management and the repository's
  [lock-down-kernel skill](../../lock-down-kernel/SKILL.md). No AGENTS.md was found
  in the checkout. CONTRIBUTING.md and SECURITY.md were read.
- GitHub connector tools are callable; Git CLI was used for repository access.
  Superpowers and Codex Security were discovered as available but uninstalled;
  installation was suggested, not completed. Their skills/scanner were not used.
  All six requested Superpowers workflows were considered but could not be
  invoked without their skill files. No independent scanner result or external
  code review is claimed. Context7 was unnecessary for direct upstream reads.
- Read all documents/configs/references named in the handoff, the current audit
  log, CI, build/signing helpers, and validators before executing the static
  configuration checks. Additional review covered Secure Boot, UKI, measured
  boot, signature reporting, and suspend diagnostics. This is bounded
  reconnaissance, not an exhaustive line-by-line audit of every helper or the
  Linux kernel.
- Exact-version upstream files were read over HTTPS from Greg Kroah-Hartman's
  stable-tree mirror at `v6.18.53`. This establishes inspected definitions, not
  signed source provenance or a whole-tree reverse-dependency audit. Kernel.org
  browsing failed; the raw stable mirror succeeded. No latest-release/EOL claim
  is made.

Evidence labels: CONFIRMED means directly established by inspected files or
recorded repository evidence; it does not mean a new physical test was run.
HIGH-CONFIDENCE INFERENCE means supported reasoning without a direct experiment.
HYPOTHESIS means a validation lead. UNKNOWN means unavailable or contradictory.
Percentages express reviewer confidence, not statistical measurements.

## FINDINGS

### F1. Audit10 checkpoint and preservation

CONFIRMED, confidence 99%: [owner runbook](../AUDIT10_OWNER_RUNBOOK.md) and
[audit log](../kernel-audit-change-log.ms), sections beginning at line 855,
record build, signing, installation, supervised boot, Secure Boot enabled,
integrity lockdown, mapper-backed ext4/LUKS/LVM root, 12 logical CPUs, connected
MT7921U, zero failed system units, and diskless KVM smoke 2/2. DMAR/IOMMU and
ordinary host VM prerequisites were available. These are historical repository
checkpoints, not a live observation from this Windows machine.

Local SHA-256 of the frozen config matches the installed-config digest recorded
in the runbook:
`121a6769868273d437d19d309a628793fabbec07f65e806568035740bd377f54`.
The audit9/audit10 file diff confirms exactly 28 `y` to `n` USB changes plus
LOCALVERSION. Both audit10 config and firmware drop-in have LF working-tree
line endings.

The signed package digest is recorded as
`8a98c461cdb4ba96e52b24ccb958100763ff2e7485cb3dcb9399fbecbff2ed44`.
The package is not present here; its bytes/signature were not independently
rechecked. The record distinguishes the signed inner EFI image from the
unsigned Debian package container correctly.

Still open: full audit10 physical device matrix; real libvirt guest boot,
networking, guest agent and confinement; s2idle plus post-resume checks;
previous-custom and distro rescue boots; default boot behavior; crash-dump
operation if required. Audit9's reported physical checks do not transfer to
audit10. USB storage passed basic detection/read/copy/eject only: the SanDisk
had a dirty FAT warning and an early unplug/lost write. Copied-file persistence
and filesystem health remain unverified. No power benefit was measured.

### F2. Architecture and effective configuration

CONFIRMED, confidence 99%: the recorded resolved audit10 snapshot retains:

- Monolithic `CONFIG_MODULES=n`, built-in MT7921U, NVMe, DM-crypt, ext4,
  loop/SquashFS, AutoFS/FUSE, USB storage/UAS, and firmware decompression.
  Module-signature enforcement is not applicable to this build; absence of
  MODULE_SIG_FORCE is not a weakening of a modular policy. DKMS is unavailable.
- Intel KVM, vhost-net, IOMMU/IRQ remapping; VFIO is retained but
  VFIO_NOIOMMU is off. No passthrough policy reversal is proposed.
- AppArmor, Yama, Landlock, integrity lockdown and
  `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"`; compiled support
  alone does not prove userspace policy quality or active runtime mediation.
- i915, UCSI/DP Alternate Mode, HDMI audio, SOF/HDA, ThinkPad ACPI,
  I2C HID/multitouch and PS/2 input. USB4 and Bluetooth remain excluded.
- Intel pstate/idle/HFI/RAPL, tickless idle, high-resolution timers and suspend.
  These enable mechanisms; residency, interrupts, wakeups, APST, ASPM, USB
  autosuspend, Wi-Fi behavior, and battery drain need matched measurements.
- BPF syscall/JIT, unprivileged-BPF-default-off, user namespaces and io_uring.
  Keep them while mapping actual sandbox, development and VM consumers. The
  repository sysctl policy is intent until checked on the running host.
- EXPERT and DEBUG_KERNEL with mmap ASLR 32/16. Do not remove the umbrella
  DEBUG_KERNEL to chase size; actual debugger/tracing exclusions are gated.

The early firmware drop-in is exact-release-scoped and includes 11 items for
i915, MT7961, SOF/topologies and signed regulatory data. Its audit10 guard must
not be renamed. Any future release needs a separate reviewed drop-in and
post-generation initramfs inspection.

### F3. Stale and contradictory documentation

CONFIRMED, confidence 99%, unless explicitly qualified:

| Location | Conflict or stale statement | Safe disposition |
| --- | --- | --- |
| README development status / control summaries | Scaffolding-era status and audit3/audit5 examples predate installed audit10 | Propose a current-status index pointing at frozen evidence |
| ISSUES.md audit2 CPU/loop/lockdown and Wi-Fi rows | Later audit3 and audit10 records demonstrate restoration of basic boot and association | Preserve historical failure; split historical remediation from current physical validation |
| ISSUES.md NETtel / synthetic radio row | Claims NETtel remains; audit10 has MTD and IEEE802154 disabled | Mark issue scope/version explicitly; do not infer every unrelated driver is gone |
| ISSUES.md GRUB row | Says latest read-back has no hostdisk error; audit10 runbook still references prior warning | UNKNOWN current environment behavior; retain manual boot guidance until owner reconciles timestamps |
| HARDWARE.md / hardware reference | audit3/audit5 or planned Secure Boot wording | Keep dated inventory facts; add separate current-state cross-reference |
| THREAT_MODEL.md / MEASURED_BOOT.md / SECURE_BOOT.md | Present-tense Secure Boot off/Setup Mode contradicts audit10 checkpoint | Report correction separately; never rerun enrollment to satisfy old prose |
| README / ARCHITECTURE / SECURE_BOOT | Modular enforcement and diagnostic-lockdown descriptions do not match monolithic config and diagnostic fragment's unchanged integrity policy | Distinguish implemented profile from design alternatives |
| UKI.md introduction | Calls default separate initramfs signed, while later text and boot-chain reference acknowledge it is not automatically authenticated | Document actual verification coverage; no evidence here establishes separate initramfs authentication |
| THREAT_MODEL boot-tampering residual | Claims essentially no residual after enablement | Too broad given separate initramfs/cmdline and unverified sealing coverage; propose narrower claim |
| SECURITY.md firmware Thunderbolt claims | Treats disablement as established; HARDWARE and runtime history leave firmware policy unresolved | Preserve USB4 exclusion; request firmware-policy evidence without changing firmware |
| hardened.config header / optional USB Ethernet assignments | Header still refers to audit8/audit9; positive dongle assignments coexist with later parent exclusions | Flag fragment intent drift; resolved audit10 and historical approved cuts are authoritative |
| docs/TESTING.md runnable list | Describes only two checks although more gates exist | Update inventory in a later docs-only proposal |

ISSUES.md source-provenance and unmeasured-power items remain applicable.
Display/UCSI and fallback tests remain open; a firmware listing or successful
boot alone cannot close them.

### F4. Build provenance and artifact identity

CONFIRMED, confidence 99%: [build-kernel.sh](../../scripts/build-kernel.sh)
accepts an existing source directory at lines 147 onward and only prints GPG
instructions. It enforces neither archive digest/signature nor extraction
freshness. It copies a base config and runs resolution, but does not establish
that the source or generated files belong to the expected release. make then
executes code from that tree. A reused/modified tree is an integrity and
reproducibility risk; exploitation requires control of build inputs or workspace.
This is not evidence that audit10 was compromised: the audit log separately
records verified tarball, fresh extraction, config resolution and package checks.

No enforced make kernelversion/kernelrelease comparison, immutable source
manifest, dedicated clean output directory, or explicit package/config identity
binding exists in this general helper. Fragment LOCALVERSION currently names
audit10, so casual reuse for a future build could reuse that identity. curl is
used but not included in REQUIRED_CMDS. Downloads write directly to the final
archive path; an interrupted file is not automatically authenticated on reuse.

[sign-kernel.sh](../../scripts/sign-kernel.sh) signs a caller-selected raw
image, not a digest-bound package/config tuple. It replaces the input before
sbverify, uses a predictable `.signed` destination, and does not enforce a
private staging directory. HIGH-CONFIDENCE INFERENCE, confidence 90%: caller
privileges plus attacker-writable staging paths could permit substitution or
symlink trouble. Not reproduced; do not run it with owner keys to test this.
The historical audit10 package workflow had extra extraction/hash checks and
must not be conflated with this generic helper.

### F5. Validation and helper trust boundaries

1. CONFIRMED, 99%: sign-kernel.sh skips a module containing a signature marker
   and later calls marker presence verification. This is not cryptographic
   validation of contents, signer, or kernel trust. It also searches only
   uncompressed `.ko` files. verify-module-signatures.sh checks signature
   presence/metadata but has no expected-key comparison. Future modular use
   needs real verification; audit10 has no loadable modules.
2. CONFIRMED, 99%: verify-secure-boot.sh prints FAIL for an unexpected release
   but finishes with successful printf, so status output is not an exit-code
   gate. It labels any matching dmesg line PASS, regardless of meaning, and does
   not recognize MODULES=n as not applicable. UNKNOWN results must remain
   distinct from successful verification.
3. HIGH-CONFIDENCE INFERENCE, 90%: suspend-diagnostics.sh uses predictable
   `/tmp/suspend-diag`, accepts an existing directory and redirects output to
   timestamp filenames. A privileged invocation with attacker-controlled
   directory/path components can follow symlinks and overwrite a target with
   diagnostic text. No exploit was run; prerequisites and host filesystem
   protections must be tested in a disposable Linux environment. It also uses
   whichever sleep mode is bracketed, rather than requiring s2idle. This is
   not an observed audit10 suspend failure.
4. CONFIRMED, 99%: the skill boot-critical validator omits the separate NR_CPUS
   minimum that preflight-check enforces. The 82 versus 83 passes reflect that
   difference, not conflicting config results. required-symbols repeats TTY;
   pass counts are not counts of independent security properties.
5. HIGH-CONFIDENCE INFERENCE, 90%: diagnostic.config requests BTF while
   hardened.config selects DEBUG_INFO_NONE; it does not explicitly select a
   DWARF mode. Upstream lib/Kconfig.debug puts BTF in the debug-info path and
   requires toolchain/pahole conditions. Diagnostic debugfs commentary also
   lacks a DEBUG_FS=y override. Reproduce diagnostic resolution before claiming
   those facilities work; do not change the production profile to fix diagnostics.

### F6. CI coverage

CONFIRMED, confidence 99%: [.github/workflows/ci.yml](../../.github/workflows/ci.yml)
runs shellcheck at error severity on top-level scripts/tests, assignment-only
duplicate checks, regex secret/dangerous-command checks, relative links and two
local tests. It correctly disclaims hardware coverage. It does not invoke the
audit8/9/10 gates, preflight security, required config check, or skill helpers.
Duplicate detection ignores `# CONFIG_X is not set` entries, so contradictory
assignment/disable lines escape it. Regex secret scans are limited detection,
not proof of no secrets, and currently print matching content into logs.
No CI run result was fetched; these are workflow-source observations.

### Static checks executed in this review

All below ran under Git Bash against the existing audit10 snapshot, after script
inspection. The command batch used `set -e` and exited 0. No hardware collector,
build, signing, installation, suspend, or kernel-source resolver was executed.

| Check | Result |
| --- | --- |
| lock-down-kernel/scripts/audit-config.sh --config CONFIG | 0 required failures |
| lock-down-kernel/scripts/validate-boot-critical.sh CONFIG | 82 pass, 0 fail, 0 warn |
| scripts/preflight-check.sh CONFIG | 83 pass, 0 fail, 0 warn; NR_CPUS=64 |
| scripts/preflight-security.sh CONFIG | 26 checks passed |
| tests/test-audit8-media-config.sh CONFIG | PASS |
| tests/test-audit9-device-config.sh CONFIG | PASS |
| tests/test-audit10-usb-config.sh CONFIG | PASS |

Here CONFIG is `config/candidate-6.18.53-lockdown-t14g3-audit10.config`.
These are static policy checks on a committed resolved snapshot, not a fresh
Kconfig resolution or hardware validation. Scripts can accept absent disabled
symbols; that must not become proof a future requested symbol survived resolution.

## PROPOSED CHANGES

### Prioritized work units

| Priority | Work unit and acceptance evidence | Risk, cost, and recovery |
| --- | --- | --- |
| P0 | Owner completes audit10 physical, real-VM, s2idle, fallback/default matrix, preserving dated results | High consequence, physical cost; retain audit9 and distro entries; blocks promotion, not independent research |
| P1 | Design source-provenance gate: authenticate uncompressed tar signature with reviewed fingerprint; pin archive hash/version; fresh private extraction/output; refuse unrecognized/dirty/reused trees; record toolchain/config/release/package hashes | Medium implementation risk, no hardware needed for fixture tests; keep existing helper unchanged until reviewed |
| P1 | Prepare CI wiring for existing current-config gates and negative fixtures; normalize both enabled/disabled entries; include skill scripts and firmware shell syntax | Low runtime risk, modest validation cost; reject missing required symbols, duplicate contradictions and policy drift; no hardware claims |
| P1 | Prepare helper fixes for private diagnostic/signing staging, verify-before-replace, reliable exit statuses and explicit UNKNOWN/N/A | Medium privilege-boundary risk; disposable fixture tests only, no real keys or host boot operations |
| P1 | Draft separate current-status/boot-trust corrections for F3 | Low risk; preserve historical evidence verbatim, owner reviews factual corrections |
| P2 | C1 test-power removal research | Modest expected security value; strong non-hardware justification; battery-policy regression test needed |
| P2 | C2 MT7601U removal research, then separately map other enabled MediaTek leaf drivers | Strong hardware evidence, low expected direct MT7921U overlap for C2; network availability consequences require real checks |
| P3 | C3 USB/IP workflow decision before any removal | Larger functional uncertainty and VM/dev/recovery cost; retain enabled until requirements are settled |
| P3 | Resolve diagnostic profile in exact source/toolchain and gate promised debug capabilities | Medium maintenance risk; isolate from production and preserve recoverable signed profile design |
| P3 | Inventory legacy watchdog ownership, filesystem/recovery consumers, hibernation and crash diagnostics | Evidence-gathering only; no proposed toggles based on idle use |

Provenance acceptance fixtures should reject: corrupt archive, wrong signer,
wrong source version, reused generated files, dirty source, wrong LOCALVERSION,
unexpected resolved delta, package/config mismatch, stale firmware release guard,
and a swapped signing input. Success should produce a manifest binding source,
requested and resolved config, compiler, release, package and inner-image hashes.
Hash/signature verification does not establish that the source is bug-free.
Use temporary downloads and private staging; allow deliberate local patches only
as an explicit hashed patch series. Build freshness is not reproducible-build proof.

CI proposals should use explicit current-candidate selection rather than demand
that historically failed snapshots satisfy today's policy. Secret detection
should redact matches and report location/rule; dangerous-command detection
should cover all executable directories with reviewed exceptions. Pin action
revisions and constrain permissions. Test skip states must be visible. None of
these proposals modifies CI in this assignment.

### Candidate Kconfig deltas for human review only

Every current value below is CONFIRMED from the committed resolved audit10
snapshot. All proposed values are intent. Whole-tree reverse dependencies and
post-resolution audit11 values are UNVERIFIED. No candidate fragment is emitted.
No candidate has a measured power benefit. Low-confidence decisions remain
questions, with the existing value retained.

#### C1. CONFIG_TEST_POWER, y -> n, conditional recommendation

| Required field | Assessment |
| --- | --- |
| Symbol/current/proposed | CONFIG_TEST_POWER: y -> n |
| Subsystem/purpose | drivers/power/supply; synthetic test AC, USB and battery supplies |
| Dependencies | Visible tristate inside POWER_SUPPLY; no direct select/imply in its definition. Whole-tree reverse selectors unverified; MODULES=n precludes m. Keep POWER_SUPPLY, ACPI_AC, ACPI_BATTERY and THINKPAD_ACPI |
| Hardware relevance | Unsupported by verified physical hardware; synthetic driver, not the real battery driver |
| Boot relevance | No root/initramfs/firmware role identified; early userspace may enumerate its synthetic supplies |
| Recovery relevance | Removes battery simulation for diagnostics; rescue kernel remains available; confirm no owner test depends on it |
| Security effect | Removes synthetic supply registration and privileged writable test parameters; no exploit or severity claim |
| Power effect | Unmeasured. HYPOTHESIS: synthetic supplies could affect userspace policy/telemetry; no demonstrated wakeup or battery improvement |
| Virtualization effect | No direct KVM dependency identified; host power policy can indirectly affect VM use |
| Suspend/resume effect | Real suspend machinery retained; verify policy sees the real battery/AC on resume |
| Regression risk | Low direct hardware risk, Medium policy risk until synthetic-supply consumers are excluded |
| Required validation | Before change, record power_supply names, types, real battery identity and UPower view; after owner-approved resolved build compare them, AC attach/detach, 75/80 thresholds, charge/discharge reporting, KDE policy, three s2idle cycles on AC/battery and post-resume charging. Full boot/recovery gate still required |
| Evidence | audit10 config line 3683; HARDWARE Battery; upstream power/supply/Kconfig and test_power.c at v6.18.53 |
| Confidence | 99% driver identity; 85% removal suitability pending owner diagnostic requirements |

Upstream implementation registers test supplies and exposes 0644 parameters.
Whether they successfully registered on audit10 is UNKNOWN; collect runtime
evidence rather than assert present-day telemetry contamination.

#### C2. CONFIG_MT7601U, y -> n, conditional recommendation

| Required field | Assessment |
| --- | --- |
| Symbol/current/proposed | CONFIG_MT7601U: y -> n |
| Subsystem/purpose | drivers/net/wireless/mediatek/mt7601u; separate MT7601U USB Wi-Fi driver |
| Dependencies | Tristate depends on MAC80211 and USB, nested in WLAN and WLAN_VENDOR_MEDIATEK; WLAN depends on NET and !S390. No direct select/imply in leaf definition. Whole-tree reverse relationships unverified |
| Hardware relevance | Unsupported by verified inventory; sole required adapter is MT7921U 0e8d:7961. Keep MediaTek parent, MT7921U and its shared mt76 dependencies |
| Boot relevance | No root dependency identified; retain MT7961 initramfs firmware and regulatory database. Do not alter frozen audit10 firmware |
| Recovery relevance | Would remove use of an MT7601U spare dongle on audit11; obtain owner confirmation that rescue-kernel recovery suffices |
| Security effect | Removes this distinct USB device-match/probe/firmware-handling path; does not establish a known vulnerability or protect all USB parsing |
| Power effect | Unmeasured; no credible battery gain established for a driver without matching hardware |
| Virtualization effect | Normal KVM unaffected in direct dependency inspection; host-backed networking and any MT7601U passthrough workflow need confirmation |
| Suspend/resume effect | MT7921U dependencies should remain; post-resume association and traffic are required |
| Regression risk | Low direct driver overlap; Medium consequence if recovery networking assumptions are wrong |
| Required validation | Full-tree selectors and USB ID-table review; seed audit10 config in verified source, resolve proposed leaf change, review full diff; owner boots, checks 0e8d:7961 binding, firmware/regdb, association, gateway/DNS/TCP traffic, reconnect after unplug/replug and three s2idle cycles; test guest networking and rescue boot |
| Evidence | audit10 config line 2730; HARDWARE Networking; upstream mt7601u/Kconfig and wireless/mediatek parent menus at v6.18.53 |
| Confidence | 99% current value and device-family mismatch; 90% suitability, subject to recovery requirements |

Other MediaTek leaves are enabled, including PCI and alternate USB families.
Do not disable the vendor submenu or shared libraries. Each additional leaf
needs its own dependency and hardware review before joining a delta.

#### C3. USB/IP, defer pending explicit workflow decision

The following table applies separately to each of the three named symbols;
the shared rows describe their common requirements. This is a conditional
proposal, not a recommendation to remove them now.

| Required field | CONFIG_USBIP_CORE | CONFIG_USBIP_VHCI_HCD | CONFIG_USBIP_HOST |
| --- | --- | --- | --- |
| Current -> proposed intent | y -> n if approved | y -> n if approved | y -> n if approved |
| Exact subsystem/purpose | drivers/usb/usbip, transport support | drivers/usb/usbip, virtual host imports remote USB | drivers/usb/usbip, exports local USB |
| Direct dependencies | NET; selects USB_COMMON and SGL_ALLOC | USBIP_CORE && USB | USBIP_CORE && USB |
| Hardware relevance | Possibly required software workflow | Virtual hubs observed in audit9 evidence | No export requirement established |
| Security mechanism | Removes USB/IP transport implementation | Removes remote-device import path | Removes local-device export path |
| Specific regression | Both import/export unavailable | Remote USB clients fail | Local USB sharing fails |

| Shared required field | Assessment for each C3 symbol |
| --- | --- |
| Parent/tristate/reverse relationships | USB_SUPPORT/HAS_IOMEM and USB menu nesting; no imply in inspected definitions. USBIP_VUDC also depends on CORE and USB_GADGET, which audit10 disables. Full reverse dependencies unverified. VHCI port/count settings become hidden if disabled; do not predict final emitted config without resolution |
| Boot relevance | Local NVMe/LUKS and physical xHCI do not identify a USB/IP requirement; confirm no remote keyboard/token/unlock workflow |
| Recovery relevance | Could remove remote USB recovery or development hardware access; local rescue fallback must be proven |
| Power effect | Unmeasured. Fewer virtual hubs does not establish fewer physical wakeups or lower power |
| Virtualization effect | KVM core is separate; remote USB sharing with guests or development hosts could be lost. USB/IP is not interchangeable with every QEMU USB redirection mechanism |
| Suspend/resume effect | Remote attachments/reconnect behavior changes; physical xHCI, MT7921U, display and charging still require regression checks |
| Regression risk | Medium to High workflow risk while requirements are UNKNOWN |
| Required validation | Owner inventories usbip services/attachments, remote devices and VM/dev consumers; approve removal only if none are required. Resolve all three plus hidden children, review full diff, test physical USB input/storage/Wi-Fi, real libvirt guest USB/network workflows, s2idle and local rescue boot |
| Evidence | audit10 config lines 6039-6043; audit log lines 858-865 explicitly defers USB/IP; upstream drivers/usb/usbip/Kconfig and drivers/usb/Kconfig at v6.18.53 |
| Confidence | 99% config/dependency observations; 60% removal suitability. Retain current values until answered |

### Upstream evidence links

- [Power supply Kconfig, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/power/supply/Kconfig)
- [Test power driver, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/power/supply/test_power.c)
- [MT7601U Kconfig, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/net/wireless/mediatek/mt7601u/Kconfig)
- [MediaTek parent, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/net/wireless/mediatek/Kconfig)
- [Wireless parent, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/net/wireless/Kconfig)
- [USB/IP Kconfig, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/usbip/Kconfig)
- [USB parent, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/Kconfig)
- [Debug information Kconfig, v6.18.53](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/lib/Kconfig.debug)

## UNVERIFIED QUESTIONS and review gate

1. Does the owner use test power supplies, alternate MediaTek dongles, USB/IP,
   remote USB tokens, or related guest/development workflows? No absence is
   inferred solely from an idle inventory.
2. What is the actual initramfs/cmdline authentication and TPM sealing policy?
   Signed vmlinuz alone does not answer this. Do not request keys or recovery
   credentials. Inspect non-secret policy/evidence with owner authorization.
3. Can the exact verified Linux 6.18.53 source/toolchain be made available in an
   existing disposable Linux environment? No new Windows host installation is
   authorized. Full reverse-dependency checks and Kconfig resolution are
   UNVERIFIED, including diagnostic BTF behavior.
4. Which firmware pre-boot Thunderbolt authorization, fallback/default boot,
   crash-dump, hibernation and watchdog behaviors are actually required and
   tested? Preserve current capabilities while evidence is incomplete.
5. Are runtime AppArmor policy, active LSMs, namespace restrictions, unprivileged
   BPF restriction, VM isolation and recovery drills recorded for audit10?
   Compiled support and static sysctl files are insufficient.

Before any audit11 Kconfig implementation, STOP for human review of the proposed
symbol delta and requirements. Subsequent authorized resolution must use a
verified source tree, exact audit10 seed, separate output directory, complete
before/after diff, required/security gates and a provenance manifest. Unexpected
resolver changes return to review. The physical owner controls compilation and
package acceptance, signing, installation, boot, physical tests, recovery and
promotion. No report or generated configuration can replace that gate.

For any future power comparison hold hardware, userspace, brightness, network,
workload, kernel parameters, firmware and battery condition constant. Collect
repeated package C-state/residency, wakeup/interrupt, pstate/HWP, i915 runtime PM,
ASPM/APST, USB/Wi-Fi runtime PM and suspend-drain measurements using the repository
benchmark protocol. Report measured effects separately from mechanisms and
hypotheses.

## Explicitly unchanged

No tracked existing file was edited. Audit10 config, firmware drop-in, package
hash records, signing/boot/runtime/hardware evidence and historical runbook
stages remain untouched. No audit11 config or deployable kernel was produced.
No build, signing, installation, boot configuration, TPM, disk, firmware, live
power policy, swap, repository administration, merge, push or commit operation
was performed. Only the local clone/research branch and this analysis artifact
were created. Existing factual errors are reported here for separate review.
