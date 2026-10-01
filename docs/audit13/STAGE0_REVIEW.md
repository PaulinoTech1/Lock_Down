# Audit13 stage-0 watchdog review

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

## Recommendation and stop gate

**Recommend no audit13 watchdog cut now.** The SE10/SE30 DMI mismatch is
useful narrowing evidence, but it does not resolve the live conflict or
justify changing a running daily-driver kernel. Obtain read-only Linux binding
evidence and authenticated-source resolution first. The owner can then decide
whether the two-leaf set is worth a separate, supervised build experiment.

Optional FUSE leaves are a separate later review. Preserve core FUSE/AutoFS,
KVM, VFIO/IOMMU, crash diagnostics, Intel graphics and SOF audio, the sole
MT7921U network path and USB storage, direct USB-C/HDMI, encrypted boot,
Snap/SquashFS, and the owner-required USB/IP core/VHCI/host paths. Do not
silently change BPF, namespaces, io_uring core, or guest integration.

**Owner gate:** Review this memo. No audit13 fragment or build begins unless
the owner explicitly approves a specific cut set after Linux-side binding
evidence and a complete resolved collateral delta are available.
