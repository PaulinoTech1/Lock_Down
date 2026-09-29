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
- **Thunderbolt sysfs state.** The owner reported a firmware disable, but a
  later live check found both NHI controllers bound to the Thunderbolt driver.
  Treat the exact firmware policy as unresolved; see the dated update below.
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
re-confirm the load-bearing facts (AX211 still absent, Thunderbolt policy,
s2idle still the only mode) at Phase 0 before building.

## 2026-09-23: external display and Thunderbolt check

The running Ubuntu 7.0.0-31-generic kernel bound PCI 00:0d.2 and 00:0d.3 to
`thunderbolt`, and UCSI ACPI exposed two Type-C ports. i915 exposed HDMI-A-1
and DP-1 through DP-4; all external connectors were disconnected. This
supersedes the earlier claim that Thunderbolt was confirmed disabled. The
candidate custom profile excludes USB4 tunneling but retains HDMI and USB-C
DisplayPort Alternate Mode. Actual monitor output requires a physical test.

## 2026-09-24: recorded before first audit3 boot (superseded below)

The machine is running stock `7.0.0-31-generic`; `mokutil --sb-state` now says
Secure Boot enabled, superseding the 21 September Setup Mode snapshot above.
The audit3 package version `6.18.53-11` is now installed. Its installed kernel
passes MOK signature verification and matches the signed artifact hash; its
installed config matches the snapshot and passes 83 boot / 26 security checks.
The generated initramfs exists and the installation log reports its GRUB entry,
but their root-readable contents still require local sudo inspection. Audit3
has not booted. Stock `7.0.0-34-generic` is also installed and was listed first
by GRUB generation; do not assume the default still selects the running,
known-good `7.0.0-31-generic` until generated GRUB state is inspected.
`/swap.img` is on the
LUKS-backed LVM ext4 root and remains unchanged. The one-boot hardware test
is tracked in [AUDIT3_BOOT_CHECKLIST.md](AUDIT3_BOOT_CHECKLIST.md); no item in
runtime checklist may be marked passed from static configuration alone.

## Remaining open items

### 2026-09-24: supplied privileged preboot inspection

The initial audit3 initramfs SHA-256 is
`50bca90a754dc6e9b0e087032ef911d4e63b931abf6555c2e9048cf8f64ebeec`.
It contains Intel microcode, crypt/dm/lvm/systemd-cryptsetup/rootfs-block,
the matching LUKS UUID `6dc6712f-ec48-4782-a37a-9cef06b82a0d`, and the
`ubuntu-vg/ubuntu-lv` ext4 root settings. It does **not** contain the expected
i915/MT7961/SOF firmware paths. A local dracut-install probe reproduced that
built-in i915/mt7921u installation copies no firmware. The exact-release
drop-in in `config/60-lockdown-audit3-firmware.conf` is prepared; its installation
and initramfs regeneration still require local sudo. Boot remains on hold.

Generated GRUB default 0 selects stock `7.0.0-34-generic`; known-good 31 and
audit3 entries remain available. Privileged grubenv output has empty
`next_entry` and no hostdisk error. Nothing is queued for one-shot boot.
Current stock journal shows legacy `snd_hda_intel`/ALC257 audio, rather than
proving SOF is active; keep candidate audio auto-selection a runtime check.

### 2026-09-24: firmware correction verified before supervised boot

The owner installed the exact-release dracut drop-in and regenerated audit3's
main initramfs. Supplied privileged inspection reports SHA-256
`de381c6969713e94ea2200cafbe9a869ae217076f4f87478e3bebc50de55ff7d`.
All three i915 firmware files, both MT7961 firmware files, SOF Alder Lake
firmware, its actual symlink target and three HDA topologies are listed.
Intel microcode and the matching LUKS/LVM/ext4 settings remain intact.
The previous initramfs backup exists, root-only, alongside the new image.
Live checks confirm the installed drop-in matches the repository, the signed
kernel/config hashes are unchanged, Secure Boot remains enabled, and the
83-check boot gate, 82-check validator and 26-check security gate pass.

### 2026-09-24: first audit3 boot

The supplied journal identifies Linux `6.18.53-lockdown-t14g3-audit3 #11`;
live state confirms it is the currently running kernel. Boot ID is
`7c6b86be-90b4-42cf-9fb1-a7c33d0674b6`. The host mounted its LUKS/LVM ext4
root, reached userspace with zero failed systemd units, and reports 12 CPUs.
Secure Boot is enabled; `/sys/kernel/security/lockdown` reports
`[integrity]`; AppArmor is enabled and in the active LSM list. The monolithic
config has `CONFIG_MODULES=n`, so `/proc/sys/kernel/modules_disabled` does not
exist on this build. TPM 2.0 is detected; DMAR translation and IRQ remapping
are active. `/swap.img` remains on the encrypted root and is unchanged.

The i915 log confirms Alder Lake DMC, GuC 70.49.4 and HuC 7.9.3 load and
authenticate, with GuC submission enabled and no GPU wedge in the supplied
excerpt. The MT7921U initializes and loads its WM firmware. Live `iw` state
shows the adapter associated to `Technocopia`, with a default route. These are
functional driver/network association signals; no external connectivity
probe was recorded. Audio initializes as HDA/ALC257; speaker, mic and headphone
tests remain outstanding. Physical input, brightness, HDMI/USB-C display,
Snap mount, Thunderbolt policy, suspend/resume and a stock fallback boot also
remain outstanding.

Two build-policy issues appear in the running config and journal. First,
`CONFIG_MTD_NETtel=y` invokes the SnapGear NETtel flash-map driver on this
ThinkPad; its `nettel_init()` maps physical address `0x20000000` (the log
reports a RAM range), raises `WARNING: __ioremap_caller`, and fails the
nonexistent BOOTCS probe. It is an isolated legacy-driver warning, not a boot
failure, but should be excluded before treating the profile as clean. Second,
`CONFIG_IEEE802154_HWSIM=y` and `CONFIG_IEEE802154_FAKELB=y` create synthetic
wpan0-wpan3 interfaces and emit recurring encryption errors about once a
minute. These test radios are outside the hardware inventory. Plan to disable
these three unrelated options, resolve Kconfig, run the gates, and make a
separately identified signed build before final validation. No config change
has been made in response to these runtime findings yet.

GRUB default remains stock `7.0.0-34-generic`; the known-good 31 entry is
available. This candidate boot does not yet establish stock fallback recovery.

Follow-up live checks on the same boot confirm `/boot/efi` is mounted vfat
with `codepage=437`, Intel microcode version `0x43b`, and all current Snap
images mounted as SquashFS on loop devices. A one-packet ping to the local Wi-Fi
gateway returned successfully (0% packet loss). No broader throughput,
external-host, or application test is recorded. NVMe health/longer I/O,
physical screen/input/brightness, audio, external display, USB-C, Thunderbolt,
suspend/resume, and stock fallback remain untested.

### Older unresolved inventory items

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
