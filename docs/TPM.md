# TPM 2.0 Usage

Hardware: discrete TPM 2.0, Nuvoton NTC0702, TIS interface (VERIFIED 2026-09-21 from the laptop inventory). Kernel path: tpm_tis / tpm_tis_core. Userspace: tpm2-tools for PCR and policy inspection.

Policy (project decision, not automation): LUKS2 + TPM2 + PIN, plus a separate OFFLINE recovery passphrase. No TPM operations are automated by this project: no auto-sealing, no auto-unsealing scripts, no unattended TPM clear. Every TPM step below is a manual admin action with the recovery passphrase at hand.

## Architecture: LUKS2 + TPM2 + PIN

- The LUKS2 volume holds the root filesystem (and any other encrypted volumes).
- A keyslot is sealed to the TPM: the TPM releases the key only when the current PCR values match the policy recorded at seal time.
- A PIN is required at boot in addition to the TPM: the sealed object is PIN-protected, so stealing the machine alone is not enough; the attacker needs the PIN too. This narrows the evil-maid window but does not close it (see limitations).
- A separate offline recovery passphrase occupies its own LUKS keyslot. It is stored on offline encrypted media, never on the machine, never in the repo. It is the recovery path for every TPM failure mode listed below.

Purpose: unattended boot is not the goal; the goal is that the disk is unreadable without either (TPM in the expected state + PIN) or the recovery passphrase. The TPM binding means a disk removed from the machine, or booted in a tampered firmware/kernel state, does not unlock.

Cost: every firmware update, kernel update, or bootloader change can invalidate the PCR policy and force a re-seal or a recovery-passphrase boot. This is operational overhead on every update cycle; budget for it. Limitation: TPM sealing does not protect a running, unlocked system, and it does not stop an attacker who observes the PIN. Recovery path: the offline recovery passphrase keyslot, which must be tested (boot with it) before it is trusted.

## PCR selection guidance

What the standard PCRs measure (general UEFI/Linux semantics; confidence High on the mapping, Medium on exactly which of these this firmware populates, since the banks have not been read on this unit):

- PCR 0: firmware code (BIOS/UEFI core). Changes on every BIOS update.
- PCR 1: firmware configuration. Changes when UEFI settings change.
- PCR 2 / PCR 3: option ROMs. On this machine: Thunderbolt is disabled and there are no option ROMs expected, but the firmware may still extend these.
- PCR 4: boot manager (shim/GRUB) that was executed.
- PCR 5: GPT partition table. Changes if the partition layout changes.
- PCR 7: Secure Boot state and the keys in use. Currently reflects Secure Boot DISABLED; it will change value when Secure Boot is enabled in Phase C.
- PCR 8 / PCR 9: bootloader and kernel measurements (GRUB measures the kernel and initramfs here on a measured-boot path).

Why binding to too many PCRs breaks: sealing to PCR 0 means every BIOS update invalidates the seal. Sealing to PCR 4/8/9 means every kernel or bootloader update invalidates the seal. A policy bound to all of 0+4+7+8+9 will demand a re-seal (or recovery passphrase) after nearly every routine update, which trains the admin to reach for the recovery passphrase reflexively and defeats the point.

RECOMMENDED conservative set: PCR 7 only, plus the PIN. Rationale:

- PCR 7 binds the seal to Secure Boot being enabled with the expected key set. An attacker who disables Secure Boot, or boots with different keys, changes PCR 7 and the seal does not open. This is the highest-value single PCR on this machine.
- PCR 7 does not change on kernel updates, initramfs rebuilds, or GRUB updates, so routine OS maintenance does not break the seal.
- PCR 7 DOES change when Secure Boot is enabled (Phase C transition: currently disabled, so the seal must be created after Phase C, or re-sealed at Phase C), and on firmware updates that touch the SB key databases.
- The PIN supplies the "something you know" factor that PCR 7 alone lacks.

OPTIONAL additions with explicit tradeoffs:
- Adding PCR 4 (boot manager) detects bootloader tampering, but breaks the seal on every GRUB/shim update. Only add if the admin commits to a re-seal procedure on every bootloader update.
- Adding PCR 0 (firmware) detects firmware replacement, but breaks the seal on every BIOS update. Only add with the same re-seal commitment, and note that a firmware attacker who controls the measurement can lie about PCR 0 anyway (see docs/MEASURED_BOOT.md limitations).
- PCR 8/9 (kernel) are redundant with Secure Boot enforcement on the kernel image itself; Secure Boot already refuses to boot an unsigned kernel. Binding the disk seal to them as well adds update churn for little marginal security. NOT recommended.

Confidence: Medium on the PCR 7-only recommendation as the right tradeoff for this machine; it is general guidance, not measured on this unit. The final PCR set must be chosen after `tpm2_pcrread` shows the actual banks and values.

## Recovery implications of each choice

- PCR 7 only + PIN: recovery passphrase needed when Secure Boot state/keys change (Phase C enablement, dbx updates, firmware updates touching SB variables) or the PIN is forgotten.
- PCR 7 + PCR 4: additionally needed on every bootloader/shim update.
- PCR 7 + PCR 0: additionally needed on every BIOS update.
- Forgotten PIN with a PIN-protected sealed object: the TPM will not release the key; the recovery passphrase is the only path. There is no PIN reset without the recovery passphrase.
- Always verify the recovery passphrase boots the machine BEFORE relying on the TPM seal. An untested recovery passphrase is not a recovery path.

## What TPM clear destroys

`TPM2_Clear` (via firmware setup, `tpm2_clear`, or a physical-presence clear) destroys: the storage root keys, all sealed objects (including the LUKS2+TPM2 sealed key), PIN protection state, and any attestation keys. After a clear, the TPM-sealed LUKS keyslot is permanently unusable. The disk is NOT wiped, the LUKS header is NOT wiped, and the offline recovery passphrase keyslot still works: that is the designed recovery path. A clear is therefore recoverable (via the passphrase) but destroys the unattended-with-PIN unlock until the seal is re-created.

Never clear the TPM without: the recovery passphrase verified working, and a plan to re-seal afterward. This project never automates a clear.

## Firmware-update implications and re-seal procedure

Every BIOS/EC/firmware update can change PCR 0 and may change PCR 7 (if SB variables are touched). Procedure:

1. Before the update: record `tpm2_pcrread` output and firmware versions (docs/FIRMWARE.md), and confirm the recovery passphrase is available and tested.
2. Perform the update (manual admin action; fwupd is never automated to flash, see docs/FIRMWARE.md).
3. Boot with the recovery passphrase (the seal will likely fail; this is expected, not an emergency).
4. Re-seal: remove the old TPM-bound keyslot, enroll a fresh seal against the new PCR values with the PIN, per the systemd-cryptenroll flow below.
5. Verify: reboot and confirm PIN+TPM unlock works, then confirm the recovery passphrase still works.

## systemd-cryptenroll flow (manual admin steps)

systemd-cryptenroll is the supported tool for binding a LUKS2 volume to the TPM2 on Ubuntu 24.04. Steps are run by the admin, interactively, with the recovery passphrase at hand:

1. Confirm the LUKS2 volume, its keyslots (`cryptsetup luksDump`), and that the recovery passphrase keyslot is present and tested.
2. Enroll: `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=true <device>`. Adjust `--tpm2-pcrs` only if the PCR decision above changes; default to 7.
3. Verify enrollment: `systemd-cryptenroll <device>` lists the TPM2 token; `cryptsetup luksDump` shows the new keyslot.
4. Reboot and test the PIN+TPM unlock. Then boot once more with the recovery passphrase to confirm it still works.
5. To remove or replace a seal: `systemd-cryptenroll --wipe-slot=tpm2 <device>` (check the exact slot first with luksDump; wiping the wrong slot destroys the recovery passphrase, which is the one unrecoverable mistake in this flow).

What is never automated: enrollment, PIN entry, re-sealing, slot wiping, TPM clear. A script that touches TPM-sealed keyslots unattended is a script that can lock the admin out unattended.
