# Unified Kernel Image (UKI) Evaluation

Posture: OPTIONAL / EXPERIMENTAL on this stack. The project's default boot-integrity path is signed vmlinuz + signed initramfs + separate kernel command line via shim, documented in docs/SECURE_BOOT.md. A UKI is not required for security, and this document never claims it is.

## What a UKI is

A Unified Kernel Image is a single UEFI PE binary that bundles, via the systemd-stub loader, everything the boot needs:

- the systemd-stub UEFI stub itself (provides the PE entry point and section handling)
- the Linux kernel image
- the initramfs
- the kernel command line (embedded as a PE section)
- OS metadata (os-release, uname, splash, and similar sections)

Purpose: one signed artifact covers kernel, initramfs, and command line together. On the classic signed-vmlinuz path, Secure Boot verifies the kernel image but does not verify the initramfs contents or the command line passed by the bootloader. A UKI closes that gap by making the command line and initramfs part of the signed binary.

Cost: tooling complexity (ukify, systemd-stub versions must match the systemd in use), larger ESP footprint (each UKI duplicates kernel+initramfs instead of sharing), and a second boot artifact pipeline to maintain alongside the classic path. On Ubuntu 24.04 the UKI workflow is newer and less battle-tested than the shim+signed-vmlinuz path.

Limitation: a UKI does not fix anything about firmware trust or physical access. It narrows the bootloader-to-kernel handoff, nothing more. Recovery path: keep the classic signed vmlinuz+initramfs boot entry working; the UKI entry is additive, never the only entry, until proven.

## Generation (ukify)

On Ubuntu 24.04, `ukify` ships with the systemd package tooling (verify availability with `command -v ukify`; version must support the sections you need). Generation is a manual admin step, never automated in this project:

1. Build the pieces: kernel image, initramfs for that kernel, chosen kernel command line, os-release for this build.
2. `ukify build` with `--linux`, `--initrd`, `--cmdline`, `--os-release`, `--stub` pointing at the matching systemd-stub, outputting a `.efi` binary.
3. Record the exact command line embedded. The embedded command line cannot be edited at boot without breaking the signature; that is the point, but it also means every command-line change requires a rebuild and re-sign.

Confidence: Medium that ukify on Ubuntu 24.04 produces bootable UKIs for this hardware; the i915 early-firmware and LUKS unlock flows inside a UKI initramfs are the parts that need a live boot test, not the PE wrapping itself.

## Signing

The UKI is a UEFI binary and is signed exactly like a kernel image: `sbsign --key <key> --cert <cert>` with the same MOK used in docs/SECURE_BOOT.md, or with `scripts/sign-kernel.sh` conventions adapted to a `.efi` target. Verification is `sbverify --cert <cert> <uki>.efi`. The signing key rules from SECURE_BOOT.md apply unchanged: offline generation, never in the repo, fingerprint recorded at enrollment and compared at enrollment time.

## Installation to the ESP and boot entry creation

1. Copy the signed UKI to the ESP, e.g. under `EFI/Linux/` or a project-specific directory. Do not overwrite the existing signed vmlinuz or the Ubuntu shim/GRUB entries.
2. Create a boot entry. Two supported mechanisms:
   - `bootctl` / systemd-boot: if the machine is switched to systemd-boot, drop-in entries or automatic UKI discovery apply. Note: this machine currently boots via shim+GRUB (Ubuntu default); switching bootloaders is itself a change with rollback implications.
   - `efibootmgr`: create a direct UEFI boot entry pointing at the UKI path on the ESP. This keeps GRUB untouched.
3. Test-boot the UKI entry manually from the firmware boot menu or the bootloader menu. Do not set it as the default until the boot test passes.

## Verification

- `sbverify` passes on the installed UKI file.
- Boot the UKI entry: full userspace comes up, LUKS unlock works, external MT7921U Wi-Fi works, s2idle suspend/resume works.
- `scripts/verify-secure-boot.sh` passes with the UKI-booted kernel.
- Confirm the running kernel command line (`/proc/cmdline`) matches the embedded command line exactly.
- Confirm the UKI boots under Secure Boot enabled (Phase C state). An unsigned or wrongly-signed UKI must be refused by shim/firmware; test this with a deliberately mis-signed copy before trusting the entry.

## Rollback

- The classic signed vmlinuz+initramfs entry and the Ubuntu distro kernel entry remain installed and bootable at all times during UKI evaluation.
- Rollback is: select the classic entry at boot, delete the UKI boot entry (`efibootmgr -b <num> -B`), remove the UKI file from the ESP. No firmware state changes are involved, so rollback is a file-and-entry operation only.
- If the UKI fails to boot, the machine is unaffected as long as the classic entries were left in place. This is why the UKI entry is never the sole entry.

## Recommendation

RECOMMENDED posture: keep the signed vmlinuz+initramfs+separate-cmdline path via shim as the default and only supported boot-integrity configuration. Evaluate a UKI as an EXPERIMENTAL hardening increment only after Phase C of docs/SECURE_BOOT.md is complete and stable, and only if the embedded-command-line property is judged worth the second artifact pipeline. Revisit this recommendation if Ubuntu's UKI tooling matures into a documented, supported LTS workflow; until then, do not present UKI as the project's security baseline.
