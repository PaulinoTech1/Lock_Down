# Audit12 stage 0: Windows-agent hardening handoff

Status: planning handoff, 30 September 2026. This document authorizes no
kernel build, signing, installation, boot change, or hardware-policy change.
It is not an audit12 candidate or a claim that audit11 passed full validation.

Owner decision, 30 September 2026: the USB/IP-related workflows are required.
The guest workspace is the intended daily driver in a Qubes OS-inspired
separation design. Preserve `CONFIG_USBIP_CORE`, `CONFIG_USBIP_VHCI_HCD`, and
`CONFIG_USBIP_HOST` at their current effective values. The original
conditional removal question is closed. The [stage-0 review](STAGE0_REVIEW.md)
records the decision and the remaining watchdog/FUSE evidence gaps.

## Objective and owner boundary

Prepare an evidence-backed, small next hardening proposal for the ThinkPad T14
Gen 3 Intel without eroding its required functions. The Windows Codex agent's
deliverable is a review memo, not a new kernel. Present initial findings to
the owner and **stop for approval before editing a Kconfig fragment or
promoting a resolved config**. The Linux owner retains source authentication,
Kconfig resolution, build, signing, deployment, physical tests, and recovery
decisions. Do not ask for, copy, or commit private signing keys or unlock data.

Begin from `origin/main` at or after commit `c6b07efed` (the audit11 KVM
checkpoint); do not base new work on the older `windows-codex` tip. Re-check
remote history and the worktree before creating a new research branch. The
authoritative baseline is
`config/candidate-6.18.53-lockdown-t14g3-audit11.config` at SHA-256
`0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`.
Treat a mismatch as a stop condition, not something to repair silently. The
resolved config is evidence; fragments and comments express intent.

Audit11 has passed a basic Secure Boot/integrity-lockdown boot, two diskless KVM
smoke boots, and a real Ubuntu guest boot to serial login with orderly
shutdown. Physical hardware, guest login/network/agent/workload,
suspend/resume, crash diagnostics, and fallback/default reboot are still open.
The guest's second launch did not show working network or a connected agent.
See [audit11 owner runbook](../AUDIT11_OWNER_RUNBOOK.md) and [issues](../../ISSUES.md).
Do not describe this as a full VM or laptop validation pass.

## Required preservation and decision boundaries

- Keep the encrypted NVMe root and dracut LUKS/LVM boot path, TPM unlock,
  Secure Boot and signed image, integrity lockdown, built-in firmware,
  ThinkPad ACPI, i915, Intel SOF/HDA audio, MT7921U Wi-Fi and signed regulatory
  database, input, USB storage, direct USB-C DisplayPort, and HDMI paths.
- Keep Snap/SquashFS, ext4, vfat/exfat, the required ISO/UDF path, AutoFS/FUSE
  until consumers are checked, Intel KVM/IOMMU/VFIO capability, and current
  crash-diagnostic support. Do not silently disable BPF, user namespaces,
  core io_uring, or a syscall facility used by the desktop/VM workflow.
- Keep USB/IP import/export and the daily-driver guest integration paths. The
  owner confirmed these workflows are required; do not infer that every guest
  uses every integration or weaken the separate hostile-analysis VM profile.
- Preserve stock Ubuntu and audit10 recovery choices. No GRUB, swap, firmware,
  BIOS, or host sysctl changes are part of this Windows stage.
- A smaller binary is not a measured power or security benefit. For each
  proposed cut, identify the reachable interface, driver binding or privileged
  path that changes, plus a plausible regression and a concrete test.

## Narrow investigation tracks

1. **USB/IP, preserve the required set.** Current effective audit11 values are
   `CONFIG_USBIP_CORE=y`, `CONFIG_USBIP_VHCI_HCD=y`, and `CONFIG_USBIP_HOST=y`.
   Re-read [audit11 reconnaissance](../audit11/RECONNAISSANCE.md), including
   observed virtual hubs and its explicit deferral. The owner confirmed remote
   USB and guest/development workflows are required. Record the actual Linux
   routing and per-guest device policy; do not propose removal of these three
   symbols. No absence-of-use claim is valid from an idle Windows inventory.
2. **Non-platform watchdog drivers, separate review.** The config contains
   numerous built-in watchdog leaves. Classify exact device IDs and
   dependencies against the Lenovo inventory, but retain watchdog core and
   any actual ACPI, Intel, firmware, suspend, or crash-diagnostic path until
   live Linux evidence settles it. Do not propose a wholesale WATCHDOG=n cut.
3. **Optional FUSE features, defer behind consumer evidence.** The current
   config has `FUSE_FS`, `FUSE_DAX`, `FUSE_PASSTHROUGH`, and `FUSE_IO_URING`
   enabled. Distinguish optional subfeatures from core FUSE/AutoFS and check
   Snap, desktop mounts, containers, and VM host workflows. Do not combine
   this with any other track in a first proposal.

The first memo should recommend at most one independently testable cut set,
or recommend **no cut** if workflow evidence is insufficient. For every symbol
in that set, show current value, proposed value, source Kconfig definition,
`depends on`/`select`/`imply` relationships, runtime exposure, boot and
recovery impact, KVM impact, test matrix, uncertainty, and rollback path.
Check Linux 6.18.53 source definitions and the [upstream Kconfig language
guide](https://docs.kernel.org/6.18/kbuild/kconfig-language.html); a text
search is not effective-config resolution.

## Windows execution contract

PowerShell/Git can inspect the tracked config, scripts and docs. Existing
offline fixtures may run in a suitable environment, but a Windows result must
be labeled `OFFLINE_FIXTURE`; it does not inspect this laptop's Linux kernel.
Use an existing trusted WSL/Linux environment only if already available; do
not install or alter one as part of this handoff. Do not substitute Windows
drivers, Device Manager, or a synthetic fixture for Linux host hardware
evidence. If the verified Linux 6.18.53 archive, detached signature, trusted
public keyring, and pinned signer fingerprint are unavailable, mark Kconfig
resolution **UNKNOWN** and hand the proposed assignments to the Linux owner.
Do not download and trust an unsigned or unpinned replacement source.

The agent should create `docs/audit12/STAGE0_REVIEW.md` with a fact/inference/
unknown ledger, evidence and exact references, candidate comparison, explicit
owner questions, and a one-set recommendation. A review-only branch and PR
may be used for that document. Do not commit a config fragment, candidate
snapshot, package, key, or machine-private validation bundle before owner
approval. Stop after presenting the findings and asking for the owner's
workflow decision. Subsequent Linux analysis must resolve a small approved
proposal from the authenticated archive, examine every changed symbol and
all gates, and request a separate build/deployment authorization.
