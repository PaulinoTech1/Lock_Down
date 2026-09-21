# Measured Boot

## What measured boot means on this machine

Measured boot is the process by which each boot component cryptographically hashes ("measures") the next component and extends the result into TPM Platform Configuration Registers (PCRs) before handing off control. On this ThinkPad T14 Gen 3, the static root of trust for measurement (SRTM) starts in UEFI firmware: the firmware measures itself into PCRs 0-1, then measures option ROMs, the boot manager (shim/GRUB), and onward. Each extend operation is append-only within a boot; PCRs reset only on platform reset.

Purpose: after boot, the PCR values are a tamper-evident log of what ran. Combined with a known-good reference, they let an admin detect that something in the boot chain differs from expected. Cost: the reference values must be recorded per firmware/kernel/bootloader combination and re-recorded on every update, or every update looks like an attack. Limitation: measurement records; it does not prevent. See below.

## How to read PCRs

With tpm2-tools installed:

- `tpm2_pcrread` : dumps all PCR banks (SHA-1 and SHA-256 if both are active).
- `tpm2_pcrread sha256:0,1,2,3,4,5,7,8,9` : reads the recommended subset in the SHA-256 bank.
- `tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements` : the firmware event log that explains WHY each PCR has its value (which component was measured into which PCR). Without the event log, PCR values are opaque hashes; with it, they are auditable.

Record a baseline: after each firmware update and after Phase C (Secure Boot enablement), save `tpm2_pcrread` output and the event log to offline media with the date and firmware version. A PCR value is only meaningful relative to a baseline taken on a known-good boot.

## What is measured and what is NOT

Measured (on the standard UEFI path; confidence High on the categories, Medium on this firmware's exact coverage until the event log is read on this unit):

- Firmware code and configuration (PCR 0, 1)
- Option ROMs, if any execute (PCR 2, 3)
- The boot manager binary that firmware executed: shim, then GRUB (PCR 4)
- GPT partition table (PCR 5)
- Secure Boot state and authority databases (PCR 7). CURRENT STATE: Secure Boot is disabled, so PCR 7 currently measures "Secure Boot off". It will change when Phase C enables Secure Boot. Any baseline recorded now is a pre-enablement baseline and must be re-taken after.
- Kernel and initramfs as measured by the bootloader (PCR 8, 9), on paths where the bootloader performs measurement.

NOT measured, and therefore not detectable via PCRs:

- Anything that runs before the SRTM starts (early firmware/BIOS regions outside the measured CRTM, Intel ME firmware). Measured boot trusts the measurer; it cannot detect a compromised measurer.
- Runtime state after boot: a kernel exploit, a malicious kernel module (if it somehow loads), or userspace tampering does not change PCRs. PCRs are a boot-time record, not a runtime monitor.
- Devices' firmware (NVMe, EC, USB peripherals) unless the platform firmware explicitly measures them. Assume not measured.
- Physical attacks that do not change measured code (cold-boot memory extraction on a running machine, bus sniffing). Note Intel TME memory encryption is enabled per BIOS, which narrows cold-boot disclosure but is unrelated to measurement.

## Secure Boot disabled: current implications

With Secure Boot off (the current, VERIFIED state), the boot chain is measured but not enforced: PCRs record that an unsigned or arbitrary kernel booted, but nothing stops it. Measurement without enforcement is an audit trail, not a control. The enforcement arrives with Phase C of docs/SECURE_BOOT.md. Until then, do not describe this machine as having a verified boot chain.

## Attestation experiments: EXPERIMENTAL

Remote or local attestation (quoting PCRs with an Attestation Key and verifying the quote against a reference) is marked EXPERIMENTAL for this project. Rationale: attestation is only as good as the reference values and the verifier, both of which are operational commitments (per-update re-baselining, a trusted verifier, AK provisioning and protection). It is a legitimate future increment after Phase C is stable and the TPM sealing workflow (docs/TPM.md) is routine. It is not part of the baseline.

If experimented with: use `tpm2_createak`, `tpm2_quote`, and verify quotes offline against recorded baselines. Never expose attestation keys or quotes as proof of security to third parties without understanding exactly what the quote covers.

## Limitations (do not overclaim)

- Measured boot does not detect firmware compromise by itself: if the firmware doing the measuring is compromised, the measurements are attacker-controlled. On this machine the practical firmware-trust anchors are Lenovo-signed updates via fwupd/LVFS (docs/FIRMWARE.md) and physical-access control, not PCRs.
- PCR values change on legitimate updates. Without disciplined re-baselining, the admin cannot distinguish an update from tampering, and the log becomes noise.
- A TPM reset/clear wipes the attestation keys and sealed state (see docs/TPM.md); measurement restarts from zero on next boot, with no continuity to prior baselines.
- Discrete TPM vs Intel PTT: this machine uses the discrete Nuvoton TPM. Do not switch to PTT; switching clears sealed state for no security benefit (per the compatibility report recommendation).
