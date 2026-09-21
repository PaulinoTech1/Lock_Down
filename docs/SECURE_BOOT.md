# Secure Boot Bringup

Status of this document: PLAN. Secure Boot is currently DISABLED on this machine (VERIFIED 2026-09-21, via the laptop inventory). The platform is in Setup Mode: no Platform Key (PK) is enrolled. Nothing in this document changes firmware state. Every enrollment or enablement step is a manual admin action.

Enrollment model: shim + MOK (Machine Owner Key). RECOMMENDED. Rationale: shim carries the Ubuntu-signed chain the distro kernel already relies on, MOK lets us enroll a project key without replacing the platform PK, and the machine can fall back to the Ubuntu-signed kernel at any point. Custom PK/KEK enrollment is OPTIONAL and NOT recommended for this machine: it raises the cost of a lost key to a firmware-level recovery problem with no matching upside on a single-user workstation.

Label convention used in this file: VERIFIED (observed on this machine), RECOMMENDED, OPTIONAL, EXPERIMENTAL, UNVERIFIED.

## Phase A: Build, boot, validate with Secure Boot OFF

Purpose: prove the custom kernel actually works before adding signature enforcement. A kernel that cannot boot, suspend, or drive the display under an unenforced Secure Boot is not fixed by enabling enforcement.

Steps:
1. Build the custom kernel per the project's kernel policy docs (MODULE_SIG_FORCE enabled in the config, so the kernel is signature-ready).
2. Install the kernel, its signed-by-placeholder modules, and initramfs alongside the Ubuntu distro kernel. Do NOT remove the distro kernel. It is the rescue kernel for the entire project.
3. Boot the custom kernel explicitly from the GRUB menu (not as default).
4. Validate: display, eDP panel backlight, keyboard/TrackPoint/touchpad, external MT7921U Wi-Fi, NVMe, s2idle suspend/resume, LUKS unlock flow, battery thresholds.
5. Record the exact kernel version string and build hash before proceeding to Phase B. Signature signing must pin to a validated build.

Exit criteria for Phase A: the custom kernel boots and passes the validation matrix on this hardware with Secure Boot disabled. If it does not, stop. Do not enroll keys to fix a broken kernel.

Cost: none beyond build time. Limitation: with Secure Boot off, module signatures are advisory (MODULE_SIG_FORCE is configured but lockdown is not active, and Secure Boot being off is visible in PCR 7 and in dmesg lockdown state). Recovery path: trivial, the distro kernel is untouched.

## Phase B: Generate keys offline, enroll via shim+MOK, sign kernel+modules

Purpose: establish the signing keys and prove the kernel and its modules verify under the enrolled key before enforcement is turned on.

Key handling rules:
- Generate the MOK private key and certificate on offline encrypted media (an air-gapped or live-USB machine with the LUKS device holding the keys). The generation commands are documented here; they are run by the admin, never by a script that commits anything.
- Private keys are NEVER committed to this repository, never stored in the repo directory, never backed up to unencrypted media. The repo `.gitignore` must cover key material (`*.key`, `*.pem`, `mok/`). This is a hard rule, not guidance.
- The public certificate (MOK.der/MOK.cer) is safe to keep in the repo if useful; the private key is not.
- Protect the private key with a strong passphrase at generation time. Losing the MOK private key does not brick the machine (shim still boots Ubuntu-signed binaries; you just cannot sign new kernels until you enroll a replacement MOK), but it does cost you the signing ability until recovery is done.

MOK enrollment procedure (manual admin steps):
1. `mokutil --import MOK.der` on the target machine. Set a one-time enrollment password when prompted. This queues the key for enrollment; nothing changes until the MOK Manager runs at next boot.
2. Reboot. The MOK Manager (shim's blue screen) appears. Select "Enroll MOK", "Continue", confirm the key fingerprint (compare against the fingerprint recorded at key generation; a mismatched fingerprint means stop), enter the one-time password, reboot.
3. Verify enrollment: `mokutil --list-enrolled` must show the new key with the expected fingerprint. `mokutil --test-key MOK.der` should report the key as enrolled.

Rollback (MOK removal):
- `mokutil --reset` removes all enrolled MOKs, or delete a single key via the MOK Manager's key-management screen at boot. This requires the one-time password flow again. Removing the MOK returns signed-by-that-key binaries to unverified status, which is exactly what you want if a key is compromised or being replaced.

Signing:
- Sign the Phase A-validated kernel image and all its modules with `scripts/sign-kernel.sh --key <key> --cert <cert> --kernel <vmlinuz> --modules-dir <dir>`. The script refuses hardcoded paths, refuses to overwrite without `--force`, refuses targets inside the repo, never generates keys into the repo dir, and verifies signatures after signing.
- Signature verification after signing is mandatory: `sbverify --cert MOK.cer /boot/vmlinuz-<version>` for the image, and `scripts/verify-module-signatures.sh` for modules once booted.

Exit criteria for Phase B: MOK enrolled with matching fingerprint, kernel image and all modules signed, `sbverify` and signature checks pass on the installed files. Secure Boot is still OFF; the machine boots as before.

Cost: key-generation and enrollment time, plus the discipline of offline key storage. Limitation: signatures mean nothing until Secure Boot is enabled; anyone with physical access and Setup Mode can still enroll their own keys. Recovery path: MOK removal, or simply not proceeding to Phase C.

## Phase C: Enable Secure Boot, verify, then make the hardened kernel default

Purpose: turn enforcement on only after every link in the chain is proven.

Order of operations (strict; do not reorder):
1. With Secure Boot still OFF, confirm the signed kernel boots from the GRUB menu and that `scripts/verify-secure-boot.sh` reports the signed custom kernel as running (it will report SB as disabled; that is expected at this step).
2. Enter UEFI setup. Enable Secure Boot. Supervisor password status should be confirmed at this point (UNVERIFIED whether one is set; a supervisor password gates who can re-disable Secure Boot, which is directly relevant to evil-maid resistance).
3. Boot. The signed custom kernel must boot under Secure Boot without manual intervention. If it does not, revert to the distro kernel and diagnose; do not disable security features to make it boot.
4. Verify: `mokutil --sb-state` reports Secure Boot enabled; `dmesg | grep -i lockdown` shows lockdown engaged; `cat /sys/kernel/security/lockdown` shows the active mode; unsigned modules are rejected (see test below).
5. Run the unsigned-module rejection test: attempt to load an unsigned or wrongly-signed module (`modprobe` of a test module signed with a different key, or a module built without signature). The kernel must refuse. Record the result.
6. ONLY after steps 1-5 pass: make the hardened kernel the default boot entry (GRUB default or boot entry order). Keep the distro kernel installed as the rescue entry indefinitely. No auto-deletion of old working kernels, ever.

Exit criteria for Phase C: Secure Boot enabled and verified, signed hardened kernel boots as default, unsigned modules rejected, distro kernel present as rescue.

Cost: loss of the ability to load unsigned modules (intended); any future kernel or module rebuild must be signed before it is bootable. Limitation: Secure Boot does not verify the initramfs command line on the non-UKI path; keep the kernel command line minimal and review it (the UKI path is evaluated separately in docs/UKI.md). Recovery path: boot the Ubuntu-signed distro kernel from the boot menu; if the MOK must go, remove it via MOK Manager.

## Setup Mode implications

While no PK is enrolled (the current state), the platform is in Setup Mode. Anyone with physical access to the machine can enroll keys: a PK, KEKs, db entries. This is a property of UEFI, not a bug, and it applies UNTIL a PK exists.

Consequences for the plan:
- Do not treat "shim is present" as "the boot chain is anchored" while in Setup Mode. The chain anchors when a PK exists and Secure Boot is enabled.
- Enrolling a PK is a separate decision from enrolling a MOK. shim+MOK works without a vendor PK change; the machine's firmware will generate or accept a PK when Secure Boot is enabled through the standard setup flow. If the firmware offers to enroll a default PK/KEK/db set, accept the vendor defaults (do not delete the Microsoft/Ubuntu db entries shim depends on) unless there is a documented reason not to.
- Evil-maid resistance claims must wait for: supervisor password set (UNVERIFIED) + Secure Boot enabled + TPM-backed disk encryption (docs/TPM.md). Until then, physical access defeats the boot chain by construction.

## Verification steps (post-enablement)

Run after Phase C, and re-run after any firmware update or re-seal:
- `mokutil --sb-state` : expect `SecureBoot enabled`.
- `efi-readvar` (if installed): expect PK present, db containing the expected entries, dbx present.
- `dmesg | grep -i -E 'secure.?boot|lockdown'` : expect Secure Boot enabled and lockdown engaged.
- `cat /sys/kernel/security/lockdown` : shows current mode; integrity or confidentiality mode under Secure Boot is the expected state.
- `scripts/verify-secure-boot.sh` : machine-readable PASS/WARN/FAIL/UNKNOWN per check. It never prints PASS for a state it cannot verify.
- `scripts/verify-module-signatures.sh` : confirms loaded modules are signed by the expected key and flags unsigned loaded modules.

## Unsigned-module rejection test procedure

1. Build (or take from a build tree) a trivial test module and sign it with a DIFFERENT key than the enrolled MOK, or leave it unsigned.
2. With the signed hardened kernel running under Secure Boot, attempt `insmod`/`modprobe` of that module.
3. Expected: refusal, with a signature-related error in dmesg (`PKCS#7 signature not signed with a trusted key` or equivalent). Record the exact message.
4. Confirm that a module signed with the enrolled MOK loads normally, proving the refusal is key-specific, not a general module-loading break.
5. Remove the test module after the test. Do not leave test modules on the system.

If an unsigned module loads successfully while Secure Boot reports enabled, treat it as a failed verification: do not make the hardened kernel default, and investigate (wrong key enrolled, lockdown not engaged, or the module path bypasses signature checks) before proceeding.

## What Secure Boot does NOT do

- It does not verify the initramfs contents on the classic signed-vmlinuz path (the UKI doc covers the bundled alternative; UKI is OPTIONAL/EXPERIMENTAL here).
- It does not protect against firmware compromise by itself; measured boot (docs/MEASURED_BOOT.md) records what ran, it does not prevent a compromised firmware from running.
- It does not replace LUKS2 disk encryption (docs/STORAGE_SECURITY.md) or TPM sealing (docs/TPM.md).
- With Secure Boot disabled (current state), module signature enforcement and lockdown are not active regardless of kernel config. MODULE_SIG_FORCE in the kernel config is preparation, not enforcement.
