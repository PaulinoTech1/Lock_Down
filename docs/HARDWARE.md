# Hardware State

Resolved hardware state for the supported unit as of 2026-09-21. This is the
authoritative input to every config decision in the repo. Labels:

- **VERIFIED**: observed on this machine via inventory or runtime checks.
- **RECOMMENDED**: not a hardware fact; a decision justified by the facts.
- **OPTIONAL**: supported but not required; enable only with a reason.
- **EXPERIMENTAL**: try only with measurement; never a default.
- **UNVERIFIED**: not yet checked on the machine; nothing is decided on it.

Serial numbers, disk serials, and MAC addresses are redacted throughout. What
was verified absent is recorded as carefully as what is present, because the
kernel config removes drivers for absent hardware.

## System

- Lenovo ThinkPad T14 Gen 3 Intel, machine type 21AJ, model 21AJS1GL06.
  VERIFIED
- BIOS N3MET29W 1.28 (2026-05-14), EC N3MHT19W, UEFI 2.7. VERIFIED
- Intel TME/MKTME enabled by BIOS. VERIFIED. Drives: no config change; document
  as cold-boot disclosure narrowing only, not a LUKS replacement.
- Secure Boot currently DISABLED; platform in Setup Mode, no PK enrolled
  (mokutil). VERIFIED. Drives: Phase 6 enrollment plan (shim+MOK, recoverable);
  physical security is the only control until then.

## CPU

- Intel Core i5-1245U, Alder Lake-U: 2P+8E, 10C/12T. VERIFIED
- intel_pstate with HWP/HFI active; C10 package states reachable. VERIFIED
- Microcode 0x43b loaded. VERIFIED (re-check at build time; microcode moves).
- 32 GB DDR4. VERIFIED
- Exact mitigation state under the running kernel: read from
  `/sys/devices/system/cpu/vulnerabilities/`, never assumed from the CPU
  generation. UNVERIFIED at doc time; runtime check required before claims.
- SMT policy under hostile-VM use: UNDECIDED (policy, not hardware).

Config decision: X86_INTEL_PSTATE, HWP/HFI, INTEL_IDLE (C-states incl. C10),
early microcode via initramfs, thermal framework as needed. SMT decision
deferred to the VM threat-model review.

## Chipset / PCH

- Intel Alder Lake PCH (SoC-integrated). VERIFIED at family level.
- Exact PCH PCI device ID: UNVERIFIED (read via `lspci -nn` at Phase 0; the
  config must not hard-code a PCH ID that was never observed).
- Intel ME present on Alder Lake-U silicon; AMT/vPro provisioning state:
  UNVERIFIED (check MEBx Ctrl+P at implementation; a provisioned-but-unused
  AMT is a remote management interface on the wired path).

Config decision: no chipset-specific switches finalized until the PCH ID is
read; ME/AMT state reported before any change, no ME firmware changes without
explicit approval.

## GPU / Display

- Intel Iris Xe ADL-P GT2, PCI 8086:46a8, i915 driver. VERIFIED
- Firmware in use: DMC 2.20, GuC 70.49.4, HuC 7.9.3. VERIFIED
- No discrete GPU. VERIFIED
- Panel: BOE NV140WUM-N43, 1920x1200, 60 Hz, 8 bpc, eDP. VERIFIED
- Current scanout XR30 (30-bit) blocks FBC; PSR unavailable in the current
  stack (stack limitation, not proven panel limitation). VERIFIED
- Backlight control path (intel_backlight vs acpi_video): UNVERIFIED.

Config decision: DRM_I915 only; exclude amdgpu, radeon, nouveau, and all other
vendor GPU drivers. Required firmware blobs: i915 adlp DMC/GuC/HuC at the
verified versions unless a newer set is validated on this panel. PSR/FBC/GuC
power tuning: EXPERIMENTAL, measured under a display-power doc, never defaults.

## Storage

- Samsung PM9A1 1 TB NVMe (OEM, Lenovo firmware HPS4NGXH). VERIFIED
- APST supported; deepest state PS4 = 5 mW. VERIFIED. APST stays on; never
  disabled without measured evidence.
- TCG Opal / SED support on this OEM firmware: UNVERIFIED (`nvme id-ctrl` at
  Phase 0). LUKS2 is the encryption boundary regardless; Opal is documentation
  only, never a LUKS replacement without explicit justification.
- OEM firmware note: this drive is serviced through Lenovo/LVFS, not Samsung
  retail channels; do not assume a retail Samsung updater applies. RECOMMENDED
  working assumption; confirm via `fwupdmgr get-devices`.

Config decision: NVME_CORE, BLK_DEV_NVME, PCI, block layer, DM_CRYPT (LUKS2),
partition types in use, APST preserved.

## Audio

- Intel PCH HDA + Realtek ALC257 analog codec; Alder Lake-P HDMI/DP digital
  audio. VERIFIED
- Runtime driver path: SOF Intel HDA (snd_sof_pci_intel_tgl family) plus
  snd_hda_intel. VERIFIED. The ALC257 is a wired HDA codec; removing Realtek
  wireless drivers has no effect on it.
- Internal microphone topology: present per SKU family; exact topology
  UNVERIFIED (privacy documentation only).

Config decision: keep SND_HDA_INTEL + SND_SOC_SOF_INTEL paths and the Realtek
HDA codec; exclude all other vendor audio drivers.

## Input

- AT PS/2 keyboard via i8042/serio. VERIFIED
- Elan PS/2 TrackPoint via psmouse. VERIFIED
- Synaptics SYNA8018 I2C touchpad via i2c-hid. VERIFIED
- ThinkPad ACPI buttons via thinkpad_acpi. VERIFIED
- Fingerprint reader: ABSENT on this unit. VERIFIED (was UNVERIFIED in the
  earlier report; runtime check confirms absence).
- Webcam: ABSENT on this unit. VERIFIED (was UNVERIFIED; runtime check
  confirms absence).

Config decision: keep i8042/serio/psmouse, I2C_HID/I2C_HID_ACPI,
THINKPAD_ACPI. Exclude uvcvideo and fingerprint kernel paths entirely. If a
different unit has them, that unit re-adds them after its own verification;
this config does not.

## Networking

- External MediaTek MT7921U USB Wi-Fi, VID:PID 0e8d:7961, on PCH xHCI bus 4
  port 1. VERIFIED. This is the ONLY network path.
- Internal Intel AX211: REMOVED and disabled. VERIFIED (was UNVERIFIED in the
  earlier report; runtime confirms removal). iwlwifi and AX211 firmware are
  excluded from the build.
- Wired Ethernet: NO PCI wired Ethernet NIC on this unit. VERIFIED (listing
  data claimed one; runtime check finds none). No e1000e/igc/r8169-class
  driver kept for a NIC that does not exist.
- Optional: USB-Ethernet dongle drivers (asix, cdc_ether, r8152) as modules.
  OPTIONAL: include only if the owner actually uses a USB-Ethernet dongle.

Config decision: USB core + xHCI + mt7921u (cfg80211/mac80211, rfkill). No
iwlwifi. No PCI Ethernet drivers. Dongle drivers OPTIONAL as modules. Any USB
authorization lockdown must whitelist 0e8d:7961 by VID:PID plus bus 4 port 1
before enforcement, or the machine loses networking at boot.

## USB

- Intel PCH USB 3.2 xHCI. VERIFIED at family level; exact controller PCI ID
  UNVERIFIED (read at Phase 0).
- The sole network path is a USB device, which makes USB policy a
  networking-availability risk, not just a security control. VERIFIED
  (architectural consequence).
- USB authorization default policy in effect: UNVERIFIED at doc time.

Config decision: USBGuard rules keyed on VID:PID plus bus/port, never VID:PID
alone; no default-deny USB policy until the whitelist is proven against the
verified adapter.

## Thunderbolt

- User-disabled in firmware. VERIFIED (user action; confirm the UEFI pre-boot
  TB authorization setting reads as expected at Phase 0).
- NHI sysfs nodes may still enumerate despite the firmware disable. VERIFIED
  (observed behavior class; check at Phase 0).
- No Thunderbolt dock, eGPU, or peripheral is used with this machine. VERIFIED
  (owner statement).

Config decision: exclude the thunderbolt kernel driver from the build. This
eliminates the Thunderbolt DMA exposure class on this unit. VT-d/IOMMU stays
required regardless, for the USB controller and other DMA-capable devices.
RECOMMENDED: verify the UEFI pre-boot TB authorization setting at Phase 0 and
record it.

## Bluetooth

- Removed by user choice. VERIFIED.
- rfkill still shows a tpacpi_bluetooth_sw switch present. VERIFIED. This is
  the ThinkPad ACPI Bluetooth kill switch device node, not a radio.
- The MT7921U adapter has a BT USB function that must never bind a driver.

Config decision: CONFIG_BT=n. Document handling so the MT7921U BT USB
function never binds: rfkill block plus a udev rule preventing driver bind on
the BT interface. If Bluetooth is ever wanted back, that is a policy reversal
with its own threat review, not a config toggle.

## TPM

- TPM 2.0, Nuvoton NTC0702, discrete TPM (not Intel PTT). VERIFIED
- Kernel path: TCG_TPM + TCG_TIS (TIS interface). Bind confirmed at runtime.
  VERIFIED
- TPM firmware version, PCR bank layout (SHA-256 vs SHA-1), EK certificate:
  UNVERIFIED at doc time; read via `tpm2_pcrread` / `tpm2_getcap` at Phase 7.

Config decision: TCG_TPM + TCG_TIS_CORE/TCG_TIS in the kernel; tpm2-tools in
userspace for PCR/policy work. Policy: LUKS2 + TPM2 + PIN with a separate
offline recovery passphrase recorded BEFORE sealing. Conservative PCR
selection once banks are read. NO automated TPM operations, ever; no TPM
clear automation. Do not switch between discrete TPM and Intel PTT: it clears
sealed state for no benefit on a machine that already has a discrete TPM 2.0.

## Virtualization

- VT-x, EPT, VPID: VERIFIED. VT-d with IRQ remapping: VERIFIED (capability;
  active enforcement on the boot command line is runtime-verified separately).
- KVM Intel intended. VERIFIED (stated and available).

Config decision: KVM_INTEL, INTEL_IOMMU with INTERRUPT_REMAP. VFIO/passthrough
default: no. IOMMU group layout checked at Phase 0; strict DMA parameters
evaluated against measured compatibility.

## Battery

- SMP FRU battery: 52.5 Wh design, ~47.8 Wh full (~91% health), 236 cycles.
  VERIFIED. Healthy for its cycle count; no replacement justification (an
  assessment, not a fact about the future).
- Charge thresholds 75/80% in use. VERIFIED.
- Threshold control path (sysfs vs thinkpad_acpi): confirm at Phase 0;
  expected sysfs on current kernels.

Config decision: power profiles must not fight the 75/80% thresholds. Exactly
one power-policy owner: KDE PowerDevil or power-profiles-daemon, decided at
implementation, never both.

## Suspend

- s2idle ONLY. VERIFIED (was UNVERIFIED in the earlier report; runtime
  confirms the firmware exposes s2idle and no S3/deep).
- Never attempt S3 on this platform.

Config decision: suspend work targets s2idle exclusively. The suspend/resume
test matrix (Phase 9) explicitly includes the external MT7921U Wi-Fi adapter
(the highest-risk resume path), NVMe recovery, audio, and graphics, plus
measured suspend battery drain.

## Firmware / LVFS

- fwupd/LVFS component coverage for MT 21AJ (BIOS, EC, NVMe, TPM): UNVERIFIED
  at doc time (`fwupdmgr get-devices` at Phase 0/12).
- Whether BIOS 1.28 is current or superseded: UNVERIFIED; check LVFS at
  implementation time. No "latest version" is quoted here because it goes
  stale in weeks.

Config decision: kernel retains EFI_VARS, EFI_RUNTIME_WRAPPER (capsule
delivery), and ESRT support. Flashing is never automated; every update
records before/after versions.

## Open items (honest list, not resolved by assumption)

1. ME/AMT provisioning state. UNVERIFIED.
2. Supervisor password set or not. UNVERIFIED.
3. Exact PCH PCI ID. UNVERIFIED.
4. TCG Opal support on the PM9A1 OEM firmware. UNVERIFIED.
5. Backlight control path (intel_backlight vs acpi_video). UNVERIFIED.
6. Full fwupd/LVFS component coverage for this MTM. UNVERIFIED.

Each is tracked in `docs/RUNTIME_VERIFICATION.md` with its resolution command.
Nothing in the build depends on any of them being a particular value.
