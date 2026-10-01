# Audit13: Windows Codex hardening handoff

Status: **review and proposal only**. Audit12 is the running Linux checkpoint;
audit13 has not been configured, built, signed, installed, or booted. This
handoff does not authorize Windows-side signing, deployment, a Git force-push,
or changes to the ThinkPad's boot, firmware, swap, or host security policy.

## Starting point and evidence

Start from the latest `origin/main` after fetching and verifying its actual
commit. Do not assume a stale `windows-codex` checkout matches `main`; preserve
any dirty work and do not reset it. The authoritative audit12 resolved config
is `config/candidate-6.18.53-lockdown-t14g3-audit12.config`, SHA-256
`444f72d745665f63acce59b7dce4fa9793140acbe56fd643deeb4aedf6dbc911`.
Its signed image package SHA-256 is
`3485262e37281c3b0b102fa62a86b2a95fbc694ada2f563225b0f59500544e35`;
the embedded signed image SHA-256 is
`ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d`.
Re-check these identities; stop if a local copy differs. Never commit private
keys, guest credentials, LUKS metadata, or machine-private validation bundles.

Audit12 has passed a Secure Boot integrity-lockdown boot to mapper-backed ext4
root with zero failed system units; two deterministic KVM smoke runs; a
disposable real Ubuntu guest's login, gateway and DNS access, bounded write
and checksum, guest-agent ping, and graceful shutdown. The owner reports
speakers, USB storage, USB Wi-Fi, microphone, HDMI, USB-C, touchpad, and
TrackPoint/nub working. One short s2idle cycle resumed; the USB MT7921U Wi-Fi
adapter re-associated and subsequently passed three gateway pings with zero
loss and a DNS lookup. See [stage 1](../audit12/STAGE1.md) and the
[owner runbook](../AUDIT12_OWNER_RUNBOOK.md) for exact evidence and caveats.

Do **not** turn those checkpoints into an unconditional production PASS.
Post-resume display/input/audio, keyboard and brightness, USB data persistence
after reconnect, actual stock-kernel fallback boot, crash-dump behavior, and
measured suspend battery drain are still open. The short s2idle cycle is not
a power benchmark. Audit11 and stock Ubuntu remain recovery choices; do not
remove them or make audit13 the default.

## First bounded hardening review

Use the project [kernel skill](../../lock-down-kernel/SKILL.md),
[hardware inventory](../HARDWARE.md), [threat model](../THREAT_MODEL.md),
[audit12 stage-0 review](../audit12/STAGE0_REVIEW.md), and the exact audit12
config. The first question is whether a *small, independently testable*
non-platform watchdog cut is justified. Audit12's journal reported nonfatal
legacy framebuffer/platform probe noise and watchdog misc-device registration
conflicts. The resolved config retains `CONFIG_WATCHDOG=y`,
`CONFIG_SOFT_WATCHDOG=y`, `CONFIG_ITCO_WDT=y`, `CONFIG_WDAT_WDT=y`, and
`CONFIG_LENOVO_SE10_WDT=y`/`CONFIG_LENOVO_SE30_WDT=y`. The earlier review
found SE10/SE30 DMI matches for Lenovo appliance types rather than this 21AJ
ThinkPad, but **did not** prove the host's active watchdog ownership or full
dependency closure. Probe noise alone is not a vulnerability or proof that a
driver can be safely removed.

Compare two real choices: (1) retain audit12's watchdog profile until Linux
binding/firmware evidence exists, or (2) propose only clearly mismatched leaf
driver assignments while preserving core and any active Intel/ACPI recovery
path. For each proposed symbol, record observed current value, source Kconfig
definition and dependencies/selectors, hardware binding evidence, reachable
interface and plausible security effect, regression risk, test, and rollback.
Keep facts, inferences, and unknowns visibly separate. If the evidence does
not justify a cut, recommend **no cut** rather than padding audit13 with one.

Optional FUSE leaves (`FUSE_DAX`, `FUSE_PASSTHROUGH`, `FUSE_IO_URING`) are a
separate later review. Do not combine them into the first watchdog proposal:
the daily-driver guest and desktop/container consumers have not been mapped.
Preserve core FUSE/AutoFS, KVM, VFIO/IOMMU, crash diagnostics, Intel graphics
and SOF audio, MT7921U and USB storage, direct USB-C/HDMI, encrypted boot,
Snap/SquashFS, and owner-required USB/IP core/VHCI/host support. Do not silently
disable BPF, namespaces, io_uring core, or a host/guest integration path.

## Windows deliverable and stop gate

1. Produce `docs/audit13/STAGE0_REVIEW.md` as an evidence-backed memo. Include
   the exact baseline commit/config digest, observed versus inferred claims,
   a small candidate comparison, effective-config resolution unknowns,
   risk/test/rollback table, and a recommendation of at most one cut set.
   Label Windows/offline checks `OFFLINE_FIXTURE`, never `LIVE_HOST_PASS`.
2. Inspect the authenticated Linux 6.18.53 source and its Kconfig relations
   if available. If the signed release archive, trusted public keyring, and
   pinned signer are absent, mark source authentication and resolution
   **UNKNOWN**. Do not substitute an unverified download or text search for
   Kconfig resolution.
3. Present that memo to the owner and stop. Do not edit a fragment, promote
   a resolved audit13 config, build, sign, install, or reboot until the owner
   approves a specific cut set and the Linux-side analyzer has shown every
   resolved collateral change. Use a review branch/PR, not a direct push to
   `main`, for the Windows stage.

After approval, the Linux worker can take a separate audit13 build decision:
authenticate upstream source, resolve the approved fragment against the exact
audit12 baseline, inspect the complete delta, run boot-critical and profile
gates, then build with a unique audit13 release identity. Signing, package
installation, initramfs/GRUB inspection, supervised boot, hardware/KVM/suspend
tests, and recovery verification remain distinct later gates. A smaller image
alone is neither a security nor a power result.
