# NVMe Power Management

Device: Samsung PM9A1 1 TB (MZVL21T0HCLR-00BH1), firmware HPS4NGXH
(VERIFIED from inventory). Attached via PCIe M.2 2280; negotiated link
width/generation REQUIRES runtime verification.

## Policy: APST preserved

APST (Autonomous Power State Transition) stays ON. It is never disabled
without measured evidence that it causes a specific failure on this drive.

- Purpose of APST: the NVMe controller autonomously drops into deeper
  power states (down to PS4 at 5 mW per the inventory) during idle, which
  is the dominant state for a laptop SSD. Disabling it raises idle power
  and temperature for no security benefit.
- Why not disable "for stability": APST bugs are drive/firmware-specific.
  This drive's firmware (HPS4NGXH) is the unit's known-good firmware; there
  is no evidence of APST misbehavior on it. Disabling a working power
  feature on suspicion is not hardening, it is superstition with a power
  bill.
- Cost of keeping APST: none observed. If resume-from-idle latency ever
  shows up in traces, measure first (`nvme get-feature -f 0x0c` to read
  the APST table, latency traces), then tune the APST table rather than
  disabling APST wholesale.
- Limitation: APST does not protect data; it is purely a power feature.
  Data-at-rest protection is LUKS2, documented elsewhere.
- Recovery path: if APST is ever disabled for diagnosis, re-enable with
  `nvme set-feature -f 0x0c -v 1` (feature 0x0c, value 1 = enabled).
  `scripts/check-nvme-power.sh` never writes feature values; it only reads.

## What the read-only script reports

`scripts/check-nvme-power.sh`:

- Auto-detects the NVMe device (scans `/dev/nvme*n1`); never assumes
  `/dev/nvme0n1`. Handles absence gracefully (drive missing or no NVMe
  at all: prints a clear message, exits non-zero, changes nothing).
- Model, firmware revision, supported power states (from `nvme id-ctrl`
  power-state descriptors where `nvme-cli` is available).
- APST status: reads feature 0x0c (autonomous power state transition)
  enablement where the tooling permits.
- Current power state / policy where observable via sysfs or `nvme-cli`.
- Controller temperature (SMART composite temperature).
- Unsafe shutdowns, media and data integrity errors (SMART log fields).
- Never writes feature values, never formats, never sanitizes. Read-only
  by construction.

## Firmware note

This is an OEM drive (Lenovo FRU firmware HPS4NGXH). Firmware updates come
through Lenovo/LVFS, not Samsung retail channels; do not assume a Samsung
retail updater applies. Firmware update state: check `fwupdmgr
get-devices` at implementation time. Never automate flashing.

## TCG Opal

Opal / self-encrypting-drive support on this OEM firmware is UNVERIFIED
(`nvme id-ctrl` security field at runtime). Do not design around Opal
until confirmed, and never treat drive-native encryption as a LUKS2
replacement without explicit justification. LUKS2 remains the data-at-rest
boundary regardless.

## Confidence notes

- APST supported, PS4 at 5 mW: VERIFIED from inventory. Confidence: High.
- APST currently enabled and effective: UNVERIFIED until the script runs
  on the machine. Confidence: Medium (default-on in nvme core).
- Firmware currency: UNVERIFIED; check LVFS at implementation time.
