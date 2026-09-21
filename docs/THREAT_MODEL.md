# Threat Model

For the supported unit only (ThinkPad T14 Gen 3, MT 21AJ, model 21AJS1GL06, in
the state documented in `docs/HARDWARE.md`). Each threat names what the project
does about it, what it costs, and where the residual risk sits. Confidence in
each assessment is marked High/Medium/Low.

## In scope (addressed by design)

- **Stolen, powered off.** LUKS2 with TPM2+PIN and an offline recovery
  passphrase keeps the data confidential. Cost: PIN at every boot, recovery
  passphrase custody. Residual: none beyond the usual brute-force economics of
  a strong passphrase and PIN. Confidence: High.
- **Drive removed and read elsewhere.** Same LUKS2 boundary. The Samsung PM9A1
  OEM firmware is not trusted for this; LUKS2 is the encryption boundary
  regardless of any Opal/SED capability (which is UNVERIFIED on this firmware).
  Confidence: High.
- **Boot tampering (bootloader/kernel replaced on disk).** Secure Boot via
  shim+MOK verifies the kernel signature; module signature enforcement covers
  what loads after. Cost: enrollment procedure, signing every build. Residual:
  none once enabled, except the Setup-Mode window below. Confidence: High
  (after Phase 6; before that, this threat is unmitigated, see evil maid).
- **Evil maid with physical access, Secure Boot enabled.** Signed boot chain
  plus TPM-sealed LUKS (conservative PCR selection) means a tampered boot
  chain fails to unseal or fails signature verification. Cost: PCR brittleness
  across updates; every firmware/kernel change must be followed by re-sealing
  validation. Residual: attacks below the measurement point (firmware implants
  that preserve PCR values) are partially addressed at best. Confidence: Medium.
- **Evil maid with physical access, Secure Boot NOT yet enabled (current
  state).** The platform is in Setup Mode with no PK enrolled. Anyone with
  physical access can enroll their own keys, replace the bootloader, or install
  a keylogger shim, and nothing in the boot chain will object. Implication:
  physical security of the machine matters absolutely until Phase 6 completes.
  Do not leave the machine unattended with untrusted parties before then, and
  re-verify firmware settings at enrollment time. Confidence: High.
- **Malicious USB device.** The only network path is a USB Wi-Fi adapter, so
  USB is both essential and the highest-risk bus. USBGuard policy is keyed on
  VID:PID plus bus/port for the verified adapter (MediaTek 0e8d:7961, bus 4
  port 1); default-deny for everything else once proven. Cost: a wrong rule
  kills networking; new USB devices need explicit authorization. Residual:
  VID:PID is spoofable, bus/port keying raises the bar but a device on the
  same port can still impersonate; the adapter's firmware itself is trusted
  hardware. Confidence: Medium.
- **Malicious Thunderbolt device / DMA attack over TB.** Eliminated as a class
  on this unit: Thunderbolt is disabled by the user in firmware and the
  thunderbolt kernel driver is excluded from the build. VT-d/IOMMU stays
  required anyway for the USB and other DMA-capable devices. Cost: none on
  this unit (no TB peripherals in use). Residual: NHI sysfs nodes may still
  enumerate; verify the UEFI pre-boot TB authorization setting at Phase 0.
  Confidence: High (given firmware disablement is verified at implementation).
- **Local malware / compromised applications.** AppArmor confinement, Yama
  ptrace scope, Landlock where applicable, Wayland session isolation, and a
  minimal application set bound what a compromised process can reach. Cost:
  profile maintenance; applications that change behavior need profile updates.
  Residual: profiles are allowlists written by a human; overly broad profiles
  silently permit, overly narrow ones break software. Confidence: Medium.
- **Credential theft (passwords, session tokens).** YubiKey-backed PAM via
  pam_u2f requires password plus physical presence for local authentication;
  SSH is disabled by default so there is no remote password surface.
  Cost: carrying the key; enrollment and backup-key custody. Residual: a
  compromised session after legitimate unlock is outside this control; see
  "stolen suspended". Confidence: High for the authentication step.
- **YubiKey theft or loss.** Treated as an expected event, not an emergency:
  backup credentials exist, revocation/re-enrollment is documented, and the
  LUKS recovery passphrase is independent of the YubiKey. Phase 17 rehearses
  this. Cost: maintaining a backup key securely. Confidence: High (procedural).
- **Privilege escalation via kernel module loading.** Module signature
  enforcement plus Lockdown refuses unsigned modules; the tailored config
  removes module families for absent hardware. Cost: out-of-tree or DKMS
  modules must be signed by the owner or they will not load. Residual: signed
  but vulnerable in-tree modules are still in-tree. Confidence: High for the
  mechanism, Medium for coverage.
- **Malicious kernel modules generally.** Same enforcement as above, plus no
  auto-loading of drivers for hardware that is not present. Confidence: Medium.
- **Untrusted VMs attacking the host or each other.** KVM with sVirt AppArmor
  confinement per VM, no device passthrough by default, no host credentials or
  sensitive mounts in untrusted VMs. Cost: performance overhead, VM image
  hygiene. Residual: VM escapes are possible; untrusted VMs are hostile by
  default and the host is still the higher-value target. Confidence: Medium.
- **Hostile VM network traffic.** nftables default-deny on the host plus
  libvirt network isolation for lab VMs; untrusted VM traffic is filtered
  before it reaches host services. Cost: rule maintenance per lab topology.
  Residual: does not inspect allowed traffic; a permitted flow is permitted.
  Confidence: Medium.
- **Offline access to a suspended machine (cold boot / memory disclosure).**
  Intel TME/MKTME is enabled by BIOS and narrows cold-boot memory disclosure;
  s2idle suspend keeps the LUKS volume unlocked, so this is mitigation, not
  prevention. Do not overclaim: memory encryption does not replace LUKS and
  does not protect a running, unlocked system. Confidence: Medium.
- **Firmware update failures.** Updates are never automated; before/after
  versions are recorded; the rescue kernel and disk image backup are refreshed
  first. Cost: manual process, slower updates. Residual: a failed flash can
  still brick; that is why the backup exists. Confidence: High (procedural).

## Partially addressed (reduced, not eliminated)

- **Firmware compromise (UEFI implants, persistent below the OS).** Secure
  Boot and measured boot raise the bar, but firmware runs before every
  control in this repo. Mitigation: manual versioned updates, LVFS/fwupd where
  covered, re-verification of settings at each phase. Residual: a sophisticated
  firmware implant survives everything here. Confidence: Low that we would
  detect one; Medium that the bar is meaningfully higher than stock.
- **Microcode flaws (CPU speculative-execution errata and friends).**
  Mitigation: early microcode loading (0x43b verified current as of
  2026-09-21; re-check at build time) plus the kernel's software mitigations,
  whose state is read from `/sys/devices/system/cpu/vulnerabilities/` rather
  than assumed from the CPU generation. Residual: microcode is Intel-signed
  binary; flaws in it are Intel's to fix. Confidence: Medium.
- **Malicious OEM firmware (NVMe, Wi-Fi adapter, EC).** The PM9A1 runs Lenovo
  OEM firmware (HPS4NGXH), updated via LVFS, not Samsung retail channels; the
  MT7921U runs MediaTek firmware. Neither is auditable by the owner.
  Mitigation: IOMMU isolation, no trust placed in device firmware for
  confidentiality. Residual: a malicious device firmware with DMA or protocol
  bugs is largely outside this project's reach. Confidence: Low for detection.
- **Invasive physical attacks (chip-off, bus sniffing, decapping).** Out of
  reach of a software project. TPM anti-hammering and PIN slow this down; they
  do not stop a lab. Confidence: Low (acknowledged, not addressed).
- **DMA from authorized devices.** IOMMU with VT-d and IRQ remapping is
  required and runtime-verified, which contains DMA from the USB controller and
  other bus masters to their assigned domains. Residual: IOMMU is a
  containment boundary with its own errata history; a device already authorized
  (the Wi-Fi adapter) with malicious firmware is the sharp edge. Confidence:
  Medium.
- **Zero-days in the kernel, firmware, or applications.** The tailored config
  and LSMs shrink exposure and bound blast radius; they do not prevent
  zero-days. The honest control here is update discipline: track the LTS
  branch, rebuild promptly, and revert to the distro kernel if the custom
  kernel cannot be kept current. Confidence: Medium for exposure reduction,
  Low for prevention.

## Out of scope (explicitly not addressed)

- **Protecting a running, unlocked machine from a present attacker.** If the
  session is unlocked and the adversary has hands on the keyboard, the game is
  over. Lock the screen; shut down for travel.
- **Network adversaries beyond the host boundary.** nftables filters the
  host's surface; it does not make hostile networks safe, anonymize traffic,
  or replace a VPN/Tor where those are needed.
- **Supply-chain compromise of Ubuntu, upstream kernel, or Lenovo firmware
  distribution.** We verify signatures where the tooling exists; we do not
  re-audit distributions.
- **Social engineering.** No technical control here stops the owner from being
  talked into disabling one.
- **Data recovery after catastrophic hardware failure without backups.** That
  is what Phase 0 and Phase 11 backups are for; without them, LUKS2 does its
  job against everyone including the owner.
- **Other machines.** The entire model is bound to the verified hardware state
  of this unit. Porting requires re-running inventory and verification.

## Assumptions this model rests on

Stated once, plainly: Lenovo firmware implements UEFI/Secure Boot enrollment
correctly; the Nuvoton TPM implements TPM 2.0 semantics and resists casual
extraction; upstream LTS and Ubuntu act in good faith; the owner guards offline
recovery materials and the machine's physical security until Secure Boot is on;
IOMMU is active and correctly isolating (runtime-verified, not assumed). If any
of these is wrong, the corresponding controls degrade, which is why the open
items in `docs/RUNTIME_VERIFICATION.md` (ME/AMT state, supervisor password,
Opal, fwupd coverage) are tracked instead of assumed.
