# NVMe Security: Samsung PM9A1 (OEM)

Drive: Samsung PM9A1 1TB, model MZVL21T0HCLR-00BH1, firmware HPS4NGXH (VERIFIED 2026-09-21 from the laptop inventory). APST supported with deepest state PS4 at 5mW; APST stays enabled (power policy never disables it without measured cause).

This is an OEM drive: firmware comes through Lenovo/LVFS, not Samsung retail channels. Do not apply Samsung retail firmware updaters to it; a retail updater must not be assumed to apply to OEM firmware, and a wrong-flash can brick the drive. See docs/FIRMWARE.md.

## APST: preserved

Autonomous Power State Transition is supported and the deepest state (PS4, 5mW) is kept enabled. Purpose: idle power savings on battery. The kernel NVMe driver manages APST; no project configuration disables it. If NVMe latency anomalies ever appear, APST is a diagnostic suspect, not a default-off knob: measure first (nvme smart-log, latency histograms under load), change only with evidence, record the change.

## TCG Opal: UNVERIFIED, do not design around it

Whether this specific OEM firmware exposes TCG Opal / self-encrypting-drive functionality is UNVERIFIED (requires `nvme id-ctrl` security-field inspection on the machine). Project position, unconditional:

- LUKS2 is the encryption boundary regardless (docs/STORAGE_SECURITY.md). This does not change even if Opal is later confirmed.
- If Opal support is ever confirmed on this firmware, document it as an ADDITIONAL layer (defense in depth: drive-level access control on top of LUKS2), never as a LUKS2 replacement. Justification: Opal implementations have a history of firmware-level flaws, the OEM firmware here is unaudited for Opal correctness, and LUKS2 is the layer this project can inspect and verify.
- Do not purchase Opal management tooling, do not take drive ownership, and do not set Opal passwords until support is confirmed AND the additional-layer role is accepted deliberately.

## Lenovo BIOS NVMe pre-boot password: OPTIONAL access-control layer

Lenovo BIOS on this generation typically offers an NVMe/drive password (pre-boot authentication). Status on this unit: configuration state UNVERIFIED; support LIKELY but not confirmed. If used, understand exactly what it is:

- Purpose: access control, not encryption. It gates whether the firmware unlocks the drive at boot. It does not encrypt anything by itself; the encryption boundary remains LUKS2.
- Value: raises the cost of casual drive removal/reuse (the drive will not unlock in another machine without the password) and blocks boot without the password. It is a second PIN-like factor at the firmware layer.
- Cost: another secret to manage, another prompt at boot, and catastrophic failure modes (see warnings). It also interacts with sleep/resume and with drive replacement.

Recommendation: OPTIONAL. Acceptable to enable only after LUKS2+TPM2+PIN is stable and the recovery passphrase is tested, and only if the admin commits to the password-management discipline below. It is never a substitute for LUKS2.

## Warnings

Read all of these before touching any NVMe password, Opal, or destructive setting. Every one of these is a known way to lose data or brick a drive.

- Lost NVMe password: if the BIOS NVMe password is forgotten and no recovery path was configured, the drive may be permanently inaccessible. Lenovo's recovery for a lost drive password is typically drive replacement, not password recovery. Record the password with the same offline discipline as the LUKS recovery passphrase, or do not set it.
- Drive replacement: an NVMe password set in BIOS is tied to that drive. If the drive is replaced under warranty or upgraded, the password configuration must be cleared/transferred deliberately; a new drive with a stale password expectation will not boot, and a password left set on a removed drive follows the drive.
- Firmware reset behavior: BIOS updates, BIOS "load defaults", or CMOS resets can change NVMe password behavior or clear the password state depending on implementation. After any firmware update, verify the NVMe password state before assuming it is unchanged (see docs/FIRMWARE.md re-verification discipline).
- Recovery limitations: there is no "forgot password" flow for a BIOS NVMe password that the admin can invoke. Vendor service may offer only a system-board or drive replacement. Treat the password as unrecoverable-by-design.
- Opal ownership / PSID revert: taking Opal ownership binds admin credentials to the drive's security provider. A PSID revert (physical-presence revert to factory) cryptographically erases the drive: all data, including LUKS headers, is destroyed instantly and unrecoverably. The PSID is printed on the drive label, which means anyone with brief physical access to the bare drive can perform it. Do not take Opal ownership casually, and understand that PSID revert is a one-command data-destruction primitive.
- Secure erase / sanitize / format: NVMe sanitize and format operations destroy all data on the drive including partition tables and LUKS headers. They are instant and unrecoverable. They are the correct tool for drive decommissioning and the wrong tool for everything else.
- Backup requirements: before ANY NVMe security operation (password set/change, Opal activation, firmware update touching the drive), verify: LUKS header backup current (docs/STORAGE_SECURITY.md), recovery passphrase tested, and a full data backup on separate media. The NVMe layer sits below LUKS; a mistake here bypasses every recovery path above it.

## Destructive commands: documentation only, with explicit warnings

The commands below are shown so the admin recognizes them and understands their blast radius. DO NOT RUN any of them without: verified backups, the recovery passphrase tested, explicit deliberate intent, and AC power. NONE of these commands are scripted in this project, and none may be added to a script.

- `nvme sanitize` : cryptographically erases the entire drive. DO NOT RUN except for deliberate decommissioning.
- `nvme format` : reformats namespaces; with secure-erase settings it destroys data. DO NOT RUN on a live system drive.
- Opal PSID revert (via sedutil or similar, only if Opal is ever confirmed): instant cryptographic erase. DO NOT RUN except for deliberate decommissioning.
- BIOS "secure erase" / drive password clear flows: understand whether the flow erases or merely clears authentication before using it. When in doubt, assume it erases.

Rule restated from docs/STORAGE_SECURITY.md: if the man page says the data cannot be recovered, it does not go in a script. This applies doubly at the NVMe layer because there is no LUKS header backup that survives a sanitize.
