# Security Policy

## Supported hardware

Exactly one machine: Lenovo ThinkPad T14 Gen 3 Intel, machine type 21AJ, model
21AJS1GL06, in the hardware state documented in `docs/HARDWARE.md` as of
2026-09-21. This policy covers no other unit, not even another T14 Gen 3.

Rationale: the kernel config is hardware-tailored. Driver inclusions and
exclusions, USB policy, and DMA posture are bound to verified facts about this
unit (AX211 removed, Thunderbolt disabled in firmware, Bluetooth removed, no
PCI NIC, no fingerprint reader, no webcam, s2idle-only suspend). A different
unit with different hardware will fail to boot, lose devices, or silently run
with the wrong trust assumptions. Porting to another unit requires re-running
the full inventory and runtime verification, not just copying the config.

## Supported kernel branch policy

- The custom kernel tracks an upstream LTS branch. The candidate at the time of
  writing is LTS 6.18 (supported to Dec 2027, verified against kernel.org on
  2026-09-21). Re-verify the branch and its end-of-life date at build time; do
  not hard-code horizons from this document.
- The maintainer is expected to track LTS point releases on a defined cadence
  and rebuild promptly for CVEs affecting the enabled subsystems.
- An unpatched custom kernel is worse than the distro kernel. If the custom
  kernel cannot be kept current, the supported configuration reverts to the
  distro kernel with the userspace hardening (Phases 1-3) intact.

## Vulnerability reporting

Report suspected vulnerabilities in this project's own artifacts (configs,
scripts, docs, profiles) via GitHub issues on the project repository. There are
no promised response times and no SLA; this is a personal project, not a
product. Do not report upstream kernel, Ubuntu, Lenovo firmware, or hardware
vulnerabilities here; report those to the respective vendor or upstream project.

What helps in a report: which file and version, what you expected, what you
observed, steps to reproduce on the supported hardware, and whether the distro
kernel behaves differently. Proof-of-concept code is welcome; live exploit
targeting of anyone's machine is not.

## Patching expectations

- Kernel: rebuild against the new LTS point release, boot, validate hardware
  and controls, then promote. The old working kernel stays as a boot entry.
- Userspace (AppArmor profiles, nftables rules, scripts): patch by editing the
  repo source and re-applying; keep a changelog entry.
- Firmware (BIOS/EC/NVMe via fwupd/LVFS where covered): never automated.
  Record before/after versions, keep the rescue kernel and disk image backup
  current before flashing.
- No auto-updates anywhere in the security path. Every change is deliberate and
  reversible.

## Trust assumptions

Be explicit about what the design takes on faith, because each one is a place
the model breaks if the assumption is wrong:

- Lenovo firmware (BIOS/EC) is assumed to implement UEFI, ACPI, and Secure Boot
  enrollment correctly. Firmware compromise is only partially addressed (see
  THREAT_MODEL).
- The Nuvoton discrete TPM implements TPM 2.0 semantics correctly and its
  sealed storage resists casual extraction. TPM clear destroys sealed secrets
  by design; no automated TPM operation is ever performed.
- Upstream LTS kernel code and the Ubuntu userspace are assumed to be
  maintained in good faith. We reduce exposure to their bugs (smaller config,
  sandboxing, LSMs); we do not claim to be immune to them.
- The user protects the offline recovery materials (LUKS recovery passphrase,
  Secure Boot/MOK keys, YubiKey backup) and the machine's physical security
  until Secure Boot is enabled. In Setup Mode, anyone with physical access can
  enroll their own keys (see THREAT_MODEL, evil maid).
- Intel TME/MKTME narrows cold-boot memory disclosure; it is not assumed to
  protect a running, unlocked system and does not replace LUKS.
- IOMMU/VT-d is assumed active and correctly isolating DMA-capable devices.
  This is runtime-verified, not assumed from the spec sheet.

## Unsupported configurations

- Any hardware other than the supported unit, including other T14 Gen 3 units.
- Secure Boot disabled as a steady state after Phase 6 (the plan enables it;
  running the hardened kernel long-term without it is unsupported).
- Custom PK/KEK enrollment instead of shim+MOK (not documented, not tested).
- Automated firmware flashing, automated TPM operations, automated kernel
  deletion.
- Thunderbolt peripherals (the driver is excluded and TB is disabled in
  firmware; re-adding TB is a re-architecture, not a toggle).
- Bluetooth (CONFIG_BT=n by user choice; the MT7921U BT USB function must never
  bind a driver).
- S3 suspend (the firmware exposes s2idle only; never attempt S3).
- Opal/SED as a LUKS2 replacement (Opal support on the PM9A1 OEM firmware is
  UNVERIFIED; LUKS2 remains the encryption boundary regardless).

## Consequences of local modifications

If you modify the kernel config, scripts, or policies locally:

- You own the resulting trust. A removed driver that turns out to be needed can
  silently disable a control (for example, dropping USB core pieces breaks the
  only network path; dropping the TPM driver breaks LUKS unlock).
- Document the change, the reason, and the rollback in the CHANGELOG or a local
  note before rebooting into it. Keep the previous working kernel entry.
- Re-run the relevant validation (hardware check, control check, suspend test)
  before the modified build becomes the default. "It booted" is not validation.
- Do not commit secrets introduced during local work. See `docs/SECRETS.md`.

## Security limitations

Stated plainly so nobody mistakes the project's scope:

- This project does not protect a running, unlocked machine from someone with
  physical access. Suspended-machine theft is in the threat model as a residual
  risk (see THREAT_MODEL).
- Firmware compromise, microcode flaws, malicious OEM firmware, invasive
  physical attacks, and zero-days are partially addressed or out of scope.
- Intel ME/AMT provisioning state on this unit is UNVERIFIED (open item). A
  provisioned-but-unused AMT would be a remote management interface; check MEBx
  before claiming the management plane is quiet.
- Memory encryption (TME/MKTME) does not replace disk encryption and does not
  protect a running system.
- The external USB Wi-Fi adapter is the sole network path and the highest-risk
  resume path; a USB policy error kills networking, and USB identity by VID:PID
  alone is weak (rules also key on bus/port).

## Recovery policy

Recovery is a first-class control, not an afterthought:

- The distro kernel is always retained as a rescue boot entry and is never
  auto-deleted. Working custom kernels are never auto-deleted either.
- LUKS recovery passphrase exists offline (paper/offline media) before TPM
  sealing is ever configured. TPM seal breakage after a firmware or kernel
  update is an expected event with a practiced recovery, not an emergency.
- Secure Boot/MOK private keys live on encrypted offline media, never in the
  repo. The MOK removal procedure is documented before Secure Boot is enabled.
- A full disk image backup exists off-machine (Phase 0), restore-tested
  (Phase 11), and refreshed before firmware changes.
- If any control cannot name its tested recovery path, it does not ship as a
  default. Recovery drills (lost YubiKey, seal break, suspected evil maid) are
  Phase 17 and are walked for real, not on paper.
