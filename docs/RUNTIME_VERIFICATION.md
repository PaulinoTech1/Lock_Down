# Runtime Verification Log

Dated log of what was actually checked on the laptop, what the answers were,
and what is still open. Dates are America/New_York. This file is evidence, not
marketing: UNVERIFIED stays UNVERIFIED until a command says otherwise.

## 2026-09-21: laptop-side answers received

The following were confirmed on the machine itself (via the owner's runtime
checks) and supersede the earlier compatibility report's open questions where
they overlap:

- **Wi-Fi / PCI network devices.** `lspci` network class shows no internal
  wireless NIC: the internal Intel AX211 was physically removed and disabled.
  The only Wi-Fi path is the external MediaTek MT7921U USB adapter
  (VID:PID 0e8d:7961) on PCH xHCI bus 4 port 1, driven by mt7921u. No PCI
  wired Ethernet NIC is present on this unit (listing data that claimed a
  native RJ-45 NIC does not match this unit).
- **Suspend mode.** `/sys/power/mem_sleep` exposes s2idle only; there is no
  S3/deep. Suspend work targets s2idle exclusively. Never attempt S3.
- **Thunderbolt sysfs state.** Thunderbolt is disabled by the user in
  firmware. NHI sysfs nodes may still enumerate despite the disable; the
  thunderbolt kernel driver is excluded from the build regardless. No
  Thunderbolt peripherals are used with this machine.
- **rfkill.** A `tpacpi_bluetooth_sw` switch is present (ThinkPad ACPI
  Bluetooth kill-switch node, not a radio). Bluetooth itself is removed by
  user choice (CONFIG_BT=n); the MT7921U BT USB function must never bind.
- **USB absence results.** `lsusb` shows no fingerprint reader and no webcam;
  both are absent on this unit (previously UNVERIFIED, now VERIFIED absent).
  uvcvideo and fingerprint kernel paths stay out of the build.
- **Audio modules.** Runtime uses the SOF Intel HDA path
  (snd_sof_pci_intel_tgl family) plus snd_hda_intel, with the Realtek ALC257
  analog codec. SND_HDA_INTEL + SND_SOC_SOF_INTEL stay; other vendor audio
  drivers go.
- **Mitigation state.** Read from `/sys/devices/system/cpu/vulnerabilities/`
  on the machine rather than assumed from the CPU generation. Microcode 0x43b
  confirmed loaded (re-check at build time).
- **Secure Boot state.** `mokutil` confirms Secure Boot DISABLED, platform in
  Setup Mode, no PK enrolled. This is the current, honest starting point for
  the Phase 6 enrollment plan (shim+MOK, then enable).

Confidence: High that these answers describe the machine as of 2026-09-21.
Hardware does not change by itself, but firmware updates and user actions can;
re-confirm the load-bearing facts (AX211 still absent, TB still disabled,
s2idle still the only mode) at Phase 0 before building.

## Remaining open items

Honestly unresolved as of 2026-09-21. Each names the resolution command.
Nothing in the build assumes an answer.

1. **ME/AMT provisioning state.** UNVERIFIED. Resolve: MEBx (Ctrl+P) at boot.
   A provisioned-but-unused AMT is a remote management interface; report state
   before any change, no ME firmware changes without explicit approval.
2. **Supervisor password set or not.** UNVERIFIED. Resolve: check at
   implementation (UEFI setup prompts). Gates who can re-disable Secure Boot;
   evil-maid-relevant.
3. **Exact PCH PCI ID.** UNVERIFIED. Resolve: `lspci -nn`. The config must not
   hard-code a PCH ID that was never observed.
4. **TCG Opal support on the PM9A1 OEM firmware.** UNVERIFIED. Resolve:
   `nvme id-ctrl` security field. Documentation only; LUKS2 remains the
   encryption boundary regardless.
5. **Backlight control path** (intel_backlight vs acpi_video). UNVERIFIED.
   Resolve at runtime. Display-power documentation only.
6. **Full fwupd/LVFS component coverage** for MT 21AJ (BIOS, EC, NVMe, TPM).
   UNVERIFIED. Resolve: `fwupdmgr get-devices`. Drives the firmware update
   workflow scope at Phase 12. Do not quote a "latest BIOS" here; it goes
   stale in weeks.

## Method note

The inventory (`HARDWARE_INVENTORY.txt`, kept outside the repo) was the
starting point; the compatibility report classified each claim; this log
records which claims survived contact with the machine. When a future check
contradicts this log, update the log with the new date and command, and
re-evaluate every config decision that depended on the old answer. Facts have
provenance here.
