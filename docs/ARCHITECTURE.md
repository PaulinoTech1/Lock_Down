# Architecture

How the machine boots, what each layer is for, where its trust comes from, and
what happens when a layer fails. Written for an experienced Linux admin who
will operate this machine.

## The full boot chain

```text
UEFI firmware (Lenovo N3MET29W, Setup Mode -> Secure Boot enabled at Phase 6)
  -> shim (Ubuntu-signed, MOK enrolled)
    -> signed UKI / kernel (MOK-signed custom kernel)
      -> initramfs (early microcode 0x43b+, LUKS unlock)
        -> LUKS2 root (TPM2 + PIN; offline recovery passphrase)
          -> custom hardened kernel (lockdown, module-sig enforcement,
             AppArmor, Yama, Landlock, IMA appraisal as evaluated)
            -> Ubuntu LTS userspace
              -> KDE Plasma (Wayland, minimal)
                -> KVM/libvirt + sVirt (untrusted VMs)
```

Each arrow is a handoff. Each handoff has a distinct trust root, because a
single compromised root must not silently own everything below it.

## The three boot paths

There are exactly three supported boot entries. No more appear without a
documented reason; no fewer exist while the project is under construction.

1. **Hardened custom kernel (default after Phase 6).** The production kernel:
   hardware-tailored config, Lockdown LSM in integrity/confidentiality mode,
   module signature enforcement, debug and tracing infrastructure removed.
   Purpose: daily use with the smallest trusted computing base we can defend.
   Cost: building, signing, and validating every update yourself. Limitation:
   a smaller config is not a correct config; a wrongly removed driver fails
   closed at boot, which is safe but means you debug it.
2. **Diagnostic custom kernel.** Same source tree, same hardware tailoring, but
   with logging, tracing, and debug options enabled and Lockdown relaxed to
   logging where needed. Purpose: troubleshoot the hardened profile without
   guessing. It is never the default. Cost: a second build to maintain.
   Limitation: it deliberately weakens some controls, so it is for diagnosis
   sessions, not daily use.
3. **Distro rescue kernel (Ubuntu stock).** Purpose: the machine always boots,
   even if both custom kernels are broken. It is ALWAYS retained and NEVER
   auto-deleted, and neither are prior working custom kernels. Cost: disk space
   for old kernels. Limitation: it carries the full distro attack surface, so
   it is a recovery tool, not a fallback daily driver.

If you cannot boot path 3, you have a firmware or hardware problem, not a
kernel problem. That distinction drives the recovery runbooks.

## Layer purposes and distinct trust roots

- **UEFI firmware.** Purpose: initialize hardware, expose boot services, host
  the Secure Boot key databases. Trust root: Lenovo's factory provisioning plus
  the keys the owner enrolls (shim+MOK at Phase 6; the platform is in Setup
  Mode with no PK until then). It is NOT trusted to be bug-free; it is trusted
  to be the layer we verify everything else against, which is why firmware
  updates are manual, versioned, and reversible.
- **shim + MOK.** Purpose: bridge the Ubuntu-signed shim to owner-signed
  kernels without a full custom PK/KEK enrollment (recoverable, lower brick
  risk). Trust root: the Machine Owner Key the owner generates and enrolls.
  Limitation: MOK enrollment happens in the pre-boot UI with physical presence;
  anyone with physical access during Setup Mode can enroll their own keys (see
  THREAT_MODEL, evil maid).
- **Signed UKI / kernel.** Purpose: only owner-signed code runs as the kernel.
  Trust root: MOK signature verification at load time, then module signature
  enforcement for everything loaded afterward. Limitation: signatures prove
  provenance, not correctness; a signed-but-buggy kernel is still buggy.
- **LUKS2.** Purpose: confidentiality of data at rest. Trust root: the TPM2
  seal plus PIN, with the offline recovery passphrase as the ultimate root.
  Limitation: protects powered-off and drive-removed states only; a running,
  unlocked system is outside its protection (see THREAT_MODEL).
- **Custom kernel + LSMs.** Purpose: shrink the attack surface (drivers for
  absent hardware removed) and constrain what even root can do (Lockdown,
  AppArmor, Yama, Landlock). Trust root: the build process and the config
  review; reproducible builds are a goal, not yet a claim. Limitation: we
  assume the kernel has bugs. The LSMs exist to bound the blast radius of
  those bugs, not to prove their absence.
- **Ubuntu LTS userspace.** Purpose: a maintained, boring base with security
  updates the project does not have to produce itself. Trust root: Ubuntu's
  archive signing and the admin's update discipline. No auto-updates in the
  security path; every change is deliberate.
- **KDE Plasma on Wayland.** Purpose: a usable desktop where applications are
  isolated from each other's input and screen content by the compositor
  protocol (Wayland's isolation vs X11's keylogging-by-design). Minimal install
  to keep the application attack surface small. Limitation: the compositor and
  toolkit still have bugs; Wayland narrows the damage, it does not end
  application compromise.
- **KVM/libvirt + sVirt.** Purpose: run untrusted workloads (analysis VMs,
  network labs) with mandatory access control confinement per VM. Trust root:
  libvirt's sVirt AppArmor labeling plus the assumption that KVM's isolation
  holds. Limitation: VM escapes are possible. Untrusted VMs are treated as
  hostile by default (see THREAT_MODEL).

## Defense in depth, without theater

The design assumes the following, because experience says they are true:

- Firmware has bugs. Mitigation: minimal trust in firmware services after boot,
  IOMMU on, Thunderbolt driver excluded, firmware updates manual and versioned.
- Kernels have bugs. Mitigation: smaller config, Lockdown, module-sig
  enforcement, LSMs, user namespaces constrained by policy, unprivileged eBPF
  restricted.
- Drivers have bugs. Mitigation: drivers for hardware that is not present are
  not built; the external USB Wi-Fi path is policy-pinned because it is the
  only network path and therefore the highest-value driver target.
- VM escapes are possible. Mitigation: sVirt confinement, no device passthrough
  by default, untrusted VMs get no host credentials and no sensitive mounts.
- Tokens get lost. Mitigation: YubiKey loss has a practiced recovery path
  (Phase 17); the LUKS recovery passphrase exists offline before TPM sealing.
- Updates fail. Mitigation: never auto-delete working kernels; every firmware
  and kernel change records before/after versions; the rescue kernel is sacred.

What this architecture does NOT do: it does not claim to stop a determined
attacker with prolonged physical access to a running machine, it does not claim
firmware is trustworthy, and it does not claim the custom kernel is safer than
the distro kernel unless it is actually kept patched. An unpatched custom
kernel is worse than the distro kernel. That sentence is load-bearing: if the
maintenance burden ever exceeds what the owner will actually do, the correct
move is to revert to the distro kernel and keep the userspace hardening.
