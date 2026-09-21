# Firmware Updates: fwupd / LVFS Workflow

Machine: ThinkPad T14 Gen 3 (MT 21AJ). Current firmware: BIOS N3MET29W 1.28, EC N3MHT19W (VERIFIED 2026-09-21 from the laptop inventory). UEFI 2.7.

Rule: firmware flashing is NEVER automated. Every update is an explicit manual admin action. No cron job, no unattended-upgrade path, no script in this project flashes firmware. `scripts/check-firmware-updates.sh` only reports; it never installs.

## Kernel prerequisites: do not interfere

The kernel must keep EFI runtime variable access and ESRT (EFI System Resource Table) support enabled:

- EFI runtime variables: required for fwupd to stage capsule updates and for `efibootmgr`/MOK tooling.
- ESRT: how fwupd enumerates updatable firmware components and their versions.
- EFI capsule delivery path: required for BIOS/EC updates via LVFS.

If a kernel configuration change ever touches EFI_VARS, EFI_RUNTIME_WRAPPER, or ESRT handling, the fwupd workflow must be re-tested before that kernel becomes default. A hardened kernel that cannot receive firmware updates trades one security property for another; do not make that trade silently.

## Components and update sources

- BIOS (UEFI firmware): via LVFS/fwupd when Lenovo publishes for this MTM. Component coverage for MT 21AJ is UNVERIFIED until `fwupdmgr get-devices` runs on the machine; Lenovo publishes broadly to LVFS for ThinkPads, but confirm per-component rather than assuming.
- EC (embedded controller): typically bundled with the BIOS capsule on ThinkPads; version it together with BIOS.
- NVMe firmware (Samsung PM9A1 OEM, fw HPS4NGXH): via Lenovo/LVFS ONLY. Do not use Samsung retail updaters (Magician or retail fwupd plugins targeting retail Samsung drives) on this OEM drive. A retail updater must not be assumed to apply; a wrong-flash can brick the drive. If LVFS offers no NVMe update for this drive, the drive stays on its current firmware until Lenovo publishes one.
- Thunderbolt firmware: N/A. Thunderbolt is disabled on this machine (per project hardware state). Do not flash Thunderbolt retimer firmware for a disabled controller; if Thunderbolt is ever re-enabled, revisit.
- TPM firmware (Nuvoton NTC0702): update only if LVFS offers it AND the update is security-relevant. TPM firmware updates can clear or invalidate sealed state; treat a TPM firmware update like a TPM clear for planning purposes (see docs/TPM.md: recovery passphrase verified, re-seal planned afterward). Never update TPM firmware casually.

## Before/after version recording

For every firmware update, record before and after:

1. Before: `fwupdmgr get-devices` output (device names, GUIDs, current versions), `tpm2_pcrread` baseline, BIOS/EC versions from firmware setup or `dmidecode -t bios`, NVMe firmware from `nvme id-ctrl`, and the Secure Boot state (`mokutil --sb-state`).
2. Perform the update as a manual admin action on AC power with suspend disabled for the duration.
3. After: re-run the same collection. Confirm versions changed as expected and nothing else changed unexpectedly.
4. Re-verify the security stack: Secure Boot still enabled and enforcing (docs/SECURE_BOOT.md verification steps), TPM seal still opens or re-seal per docs/TPM.md, PCR baselines re-taken (docs/MEASURED_BOOT.md), NVMe password state confirmed if configured (docs/NVME_SECURITY.md warnings on firmware-reset behavior).
5. Store the before/after record with the date on offline media alongside the PCR baselines. Firmware history is part of the machine's audit trail.

Purpose: version recording turns "the firmware was updated" from an assertion into evidence, and catches updates that silently change security-relevant state (SB variables, TPM behavior, password state). Cost: a few minutes per update. Limitation: version strings do not prove the firmware is genuine; the trust anchor is Lenovo's LVFS signing chain plus physical-access control.

## Rescue paths when fwupd cannot update a component

If `fwupdmgr get-devices` does not list a component, or `fwupdmgr get-updates` offers nothing while Lenovo's support site shows a newer version:

1. Check LVFS coverage for the exact MTM (21AJ) rather than the model family; OEM and regional variants differ.
2. Lenovo bootable ISO: Lenovo publishes bootable firmware update ISOs (bootable via USB). This is the supported fallback for BIOS/EC updates when LVFS lacks coverage. Procedure: download from Lenovo support for the exact MTM, verify the published checksum, boot the ISO from USB, apply on AC power, then run the full before/after recording above.
3. For the NVMe drive: if neither LVFS nor Lenovo offers an update, do not seek third-party firmware. The drive runs its shipped firmware until the vendor publishes an update.
4. If a fwupd update fails mid-flash: do not power off. ThinkPad firmware updates are generally crash-safe (dual-bank), but a failed flash followed by a power loss is the brick scenario. Let fwupd report, record the failure, and use the Lenovo bootable ISO path for recovery.

What is never done: flashing firmware from unverified sources, interrupting a flash, or updating firmware over battery power.

## Interaction with the rest of the project

- Secure Boot: firmware updates can touch SB variables (dbx updates especially). After any update, re-run docs/SECURE_BOOT.md verification; a dbx update that revokes a bootloader in use will refuse to boot it, which is the mechanism working as intended, but the admin must know before rebooting into a revoked binary.
- TPM sealing: any BIOS/EC update is a re-seal event until proven otherwise (docs/TPM.md re-seal procedure). Plan the update with the recovery passphrase at hand.
- Measured boot baselines: re-take after every firmware update (docs/MEASURED_BOOT.md). The old baseline is stale the moment the firmware changes.
