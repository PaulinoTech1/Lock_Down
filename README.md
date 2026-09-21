# Lock_Down

A hardware-tailored, security-first Linux workstation build for **one specific laptop**:
a Lenovo ThinkPad T14 Gen 3 Intel (machine type 21AJ, model 21AJS1GL06).

This is not a distro. It is a reproducible set of kernel configs, userspace hardening,
and procedures that turn a stock Ubuntu LTS install on this machine into a
defense-in-depth workstation. Every decision in this repo is justified by hardware
that was actually verified on this unit (see `docs/HARDWARE.md` and
`docs/RUNTIME_VERIFICATION.md`). Anything not verified is labeled UNVERIFIED and
stays out of the build until it is checked on the machine.

## What this project does NOT claim

No "unhackable", no "military grade", no "zero trust OS", no "quantum-proof".
An unpatched custom kernel is worse than the distro kernel, and this repo says
that outright in `docs/ARCHITECTURE.md`. Hardening raises the cost of attack; it
does not eliminate it. See `docs/THREAT_MODEL.md` for what is in scope, what is
partially addressed, and what is explicitly out of scope.

## Target hardware

- Lenovo ThinkPad T14 Gen 3 Intel, MT 21AJ, model 21AJS1GL06
- BIOS N3MET29W 1.28 (2026-05-14), EC N3MHT19W, Intel TME/MKTME enabled by BIOS
- Core i5-1245U (Alder Lake-U, 2P+8E, 10C/12T), microcode 0x43b, 32 GB DDR4
- Intel Iris Xe ADL-P GT2 (8086:46a8), no discrete GPU
- Samsung PM9A1 1 TB NVMe (APST, PS4 = 5 mW)
- Networking: external MediaTek MT7921U USB Wi-Fi (0e8d:7961) ONLY. The internal
  AX211 was physically removed and disabled. No PCI wired Ethernet NIC on this unit.
- Thunderbolt disabled by the user in firmware. Bluetooth removed by user choice
  (CONFIG_BT=n). No fingerprint reader, no webcam on this unit.
- TPM 2.0: Nuvoton NTC0702 discrete TPM. Policy: LUKS2 + TPM2 + PIN with a
  separate offline recovery passphrase.
- Suspend: s2idle only (no S3). Battery 52.5 Wh design, 75/80% charge thresholds.

Serial numbers, disk serials, and MAC addresses are deliberately redacted everywhere.
See `docs/HARDWARE.md` for the full resolved state with per-item classification.

## Major security controls

Each control below names its purpose, its cost, its limitation, and its recovery
path. Nothing here is claimed to "make the system secure"; each reduces a specific
attack surface under stated assumptions.

- **Custom hardware-tailored kernel** (LTS branch, 6.18 candidate, re-verify at
  build time). Removes drivers for hardware this machine does not have (AMD/NVIDIA
  GPUs, unrelated Wi-Fi vendors, unused subsystems), which shrinks the trusted
  computing base. Cost: you own patching and rebuilds. Limitation: the build only
  tracks the LTS branch you choose; a missed CVE window leaves you exposed.
  Recovery: the distro kernel is ALWAYS retained as a rescue boot entry and is
  never auto-deleted, along with every prior working custom kernel.
- **Secure Boot via shim + MOK**, enabled only AFTER the custom kernel is built,
  booted, and validated (the platform is currently in Setup Mode with no PK
  enrolled). Purpose: anchor the boot chain. Cost: one-time enrollment procedure
  with a key custodian. Limitation: in Setup Mode, anyone with physical access can
  enroll their own keys, so physical security matters until Secure Boot is on.
  Recovery: MOK removal procedure documented; rescue kernel remains bootable.
- **LUKS2 full-disk encryption with TPM2 + PIN**, plus a separate offline
  recovery passphrase. Purpose: data confidentiality when the machine is powered
  off or the drive is removed. Cost: PIN entry at every boot; PCR brittleness
  after firmware/kernel updates. Limitation: does not protect a running, unlocked
  system (see `docs/THREAT_MODEL.md`, "stolen suspended"). Recovery: the offline
  recovery passphrase unlocks the volume when TPM sealing breaks.
- **AppArmor + Yama + Landlock + Lockdown LSM + module signature enforcement**.
  Purpose: constrain processes, ptrace, unprivileged sandbox escapes, and
  unsigned kernel module loading. Cost: profile maintenance when applications
  change behavior. Limitation: profiles are allowlists that must be tested, not
  magic; a misconfigured profile silently breaks software or silently permits it.
  Recovery: boot the diagnostic profile (permissive logging, same kernel).
- **nftables default-deny host firewall**. Purpose: reduce network attack surface
  on untrusted networks. Cost: rule maintenance for new services. Limitation: it
  does not inspect what leaves through allowed ports. Recovery: console or the
  rescue kernel to reset rules.
- **KVM/libvirt with sVirt AppArmor confinement** for untrusted VMs. Purpose:
  isolate analysis VMs from the host and from each other. Cost: performance
  overhead and VM image management. Limitation: VM escapes are possible; treat
  untrusted VMs as hostile by default (see THREAT_MODEL).
- **YubiKey-backed PAM via pam_u2f** (FIDO2/U2F, password plus physical presence).
  SSH disabled by default. Purpose: phishing-resistant local authentication.
  Cost: you must carry the key. Limitation: if the key is lost or stolen, the
  recovery path is the offline recovery credential, so guard it accordingly.
- **USB device policy anchored on the verified adapter** (MediaTek 0e8d:7961 on
  bus 4 port 1). Purpose: bound the damage a malicious USB device can do, since
  the only network path is USB. Cost: a wrong policy kills networking. Limitation:
  VID:PID alone is weak identity; rules also key on bus/port.
- **Thunderbolt kernel driver excluded; VT-d/IOMMU stays required.** Purpose:
  eliminate the Thunderbolt DMA exposure class, since the user disabled TB in
  firmware and uses no TB peripherals. Cost: none on this unit (nothing uses TB).
  Limitation: NHI sysfs nodes may still enumerate; IOMMU must still be active for
  the USB and other DMA-capable devices. Recovery: re-enable in firmware and
  rebuild with the driver if usage ever changes.

## Usability goals

A hardened machine that never gets used is a failed project. The targets:

- Boots unattended to a LUKS PIN prompt, then to a working KDE Plasma Wayland
  session with Wi-Fi up, without manual module or firmware juggling.
- Daily use (browser, terminal, VMs, development) works without disabling a
  control "temporarily" and forgetting to re-enable it. Every control has a
  documented, supported way to do the common thing.
- Power behavior is predictable: s2idle suspend/resume tested with the external
  USB Wi-Fi adapter in the test matrix, battery thresholds respected, one
  power-policy owner (no fights between PowerDevil and power-profiles-daemon).
- Maintenance is boring: kernel rebuilds follow a checklist, updates are never
  automated, and every firmware/kernel change records before/after versions.

## Development status

Early construction. As of 2026-09-21 the repo has directory scaffolding and this
documentation set. Kernel configs, build scripts, and test procedures are being
added in subsequent phases. Nothing here should be treated as production-ready
until the phase checklists say so.

## Warnings

- This project targets ONE machine (MT 21AJ, model 21AJS1GL06, with the
  hardware state in `docs/HARDWARE.md`). Running these configs on a different
  unit, even another T14 Gen 3, is UNSUPPORTED and may fail to boot or silently
  drop hardware support. See `SECURITY.md`, "Unsupported configurations".
- An unpatched custom kernel is worse than the distro kernel. If you stop
  tracking the LTS branch, revert to the distro kernel.
- The distro kernel is ALWAYS retained as rescue. Never auto-delete working
  kernels. A boot entry you cannot remove yourself from is a brick.
- No secrets in this repo, ever. See `docs/SECRETS.md`. Secure Boot keys, MOK
  private keys, LUKS recovery passphrases, TPM secrets, SSH private keys,
  firmware passwords: all live offline or on the hardware, never in git.
- Firmware flashing is never automated. Every update records before/after versions.

## Installation phases

Each phase is a checkpoint. You can stop after any phase and the machine still
works; later phases only add controls on top of a verified base.

- **Phase 0**: Inventory and backup. Record the machine state (this is where
  `docs/HARDWARE.md` and `docs/RUNTIME_VERIFICATION.md` come from). Take a full
  disk image backup to separate media and verify you can restore from it.
- **Phase 1**: Ubuntu LTS base install (24.04 family), minimal, with LUKS2.
- **Phase 2**: Distro-kernel baseline. Confirm every device works on the stock
  kernel: Wi-Fi, display, audio, input, suspend/resume, battery thresholds.
- **Phase 3**: Userspace hardening on the distro kernel. AppArmor profiles,
  nftables, sysctl, USBGuard rules keyed to the verified adapter, pam_u2f,
  SSH disabled.
- **Phase 4**: Custom kernel build (hardened profile), booted with Secure Boot
  OFF. Validate all hardware and the userspace controls against it.
- **Phase 5**: Diagnostic kernel profile (same source, logging/debug enabled)
  as a second boot entry for troubleshooting.
- **Phase 6**: Secure Boot enrollment (shim + MOK), then enable Secure Boot.
  Verify signatures, test unsigned-module rejection, document MOK removal.
- **Phase 7**: LUKS2 + TPM2 + PIN sealing with conservative PCR selection.
  Record the recovery passphrase offline FIRST, then seal.
- **Phase 8**: KVM/libvirt with sVirt confinement; VM profiles for trusted,
  untrusted-analysis, and network-lab use.
- **Phase 9**: Suspend/resume validation matrix (s2idle), including the USB
  Wi-Fi adapter and NVMe recovery.
- **Phase 10**: Power tuning (intel_pstate/HWP, thresholds, single policy owner).
- **Phase 11**: Backup and recovery drills. Prove the disk image restores, the
  LUKS recovery passphrase works, and the rescue kernel boots.
- **Phase 12**: Firmware review (BIOS/EC/NVMe via fwupd/LVFS where covered),
  recording before/after versions. Never automated.
- **Phase 13**: Documentation freeze. ARCHITECTURE, THREAT_MODEL, HARDWARE, and
  runbooks match the running system.
- **Phase 14**: Adversarial self-review. Walk the threat model against the
  running machine; fix or honestly document every gap.
- **Phase 15**: Operational handover. Daily-driver trial period on the hardened
  kernel with a log of every friction point and its resolution.
- **Phase 16**: Kernel update procedure drill. Rebuild against the new LTS
  point release, boot, validate, then promote.
- **Phase 17**: Incident rehearsal. Lost YubiKey, TPM seal break after update,
  suspected evil maid: walk each recovery path for real.
- **Phase 18**: Benchmarking. Power, suspend drain, and performance baselines
  so regressions are measurable, not vibes.

## Recovery philosophy

Every control ships with a way back, tested before the control becomes the
default. The hierarchy, in order:

1. **Rescue kernel** (distro): always present, always bootable, never deleted.
2. **Prior working custom kernels**: never auto-deleted; the last known-good
   build is a boot entry, not a memory.
3. **Diagnostic profile**: same kernel source with logging enabled, for when the
   hardened profile misbehaves and you need to see why.
4. **Offline secrets**: LUKS recovery passphrase on paper/offline media, Secure
  Boot/MOK keys on encrypted offline media, YubiKey backup credentials. These
  exist because TPM seals break and tokens get lost.
5. **Disk image backup**: Phase 0 and Phase 11 artifacts, stored off-machine,
  restore-tested.

If a control cannot name its recovery path, it does not ship.

## Architecture diagram (text)

```text
                    +-----------------------------+
                    |  Lenovo UEFI 2.7 (N3MET29W) |
                    |  SB: Setup Mode -> enabled |
                    |  TB: disabled in firmware  |
                    +-------------+---------------+
                                  |
                    +-------------v---------------+
                    |  shim + MOK (post Phase 6)  |
                    |  verifies UKI / kernel sig  |
                    +-------------+---------------+
                                  |
              +-------------------+-------------------+
              |                   |                   |
   +----------v---------+ +-------v--------+ +--------v--------+
   | Hardened custom    | | Diagnostic     | | Distro rescue   |
   | kernel (default)   | | custom kernel  | | kernel (Ubuntu) |
   | lockdown, sig-enf  | | logging build  | | never deleted   |
   +----------+---------+ +-------^--------+ +--------^--------+
              |                   |                   |
              +-------------------+-------------------+
                                  |
                    +-------------v---------------+
                    |  LUKS2 (TPM2 + PIN;         |
                    |  offline recovery key)      |
                    +-------------+---------------+
                                  |
                    +-------------v---------------+
                    |  Ubuntu LTS + AppArmor +    |
                    |  Yama + Landlock + nftables |
                    |  + USBGuard + pam_u2f       |
                    +-------------+---------------+
                                  |
                    +-------------v---------------+
                    |  KDE Plasma (Wayland)       |
                    +-------------+---------------+
                                  |
                    +-------------v---------------+
                    |  KVM/libvirt + sVirt        |
                    |  (untrusted VMs isolated)   |
                    +-----------------------------+

Trust roots, per layer:
  firmware      -> Lenovo BIOS + (later) Secure Boot PK/KEK/MOK
  bootloader    -> shim signature db
  kernel        -> MOK-signed UKI; module signature enforcement
  disk          -> LUKS2 passphrase/TPM seal (offline recovery key)
  userspace     -> AppArmor policy, PAM (password + YubiKey)
  VMs           -> libvirt + sVirt confinement (hostile by default)
```

See `docs/ARCHITECTURE.md` for the full chain, the three boot paths, and the
defense-in-depth rationale (no theater: we assume firmware, kernels, and drivers
have bugs).
