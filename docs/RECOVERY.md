# Recovery

Every failure mode below ends at a bootable, signed DISTRO rescue kernel.
There are no weak emergency bypass users, no passwordless rescue accounts,
and no "boot to a root shell" shortcuts. Recovery authenticates the same
way normal operation does, or it does not happen.

Standing prerequisites (set up BEFORE they are needed; recovery without
them is improvisation, not a plan):

- The Ubuntu distro kernel is always installed and always a boot entry.
  It is never auto-removed.
- At least one previous known-good custom kernel is kept; old working
  kernels are never auto-deleted.
- LUKS recovery passphrase recorded offline (paper, sealed) AND a LUKS
  header backup stored offline. Both verified by a test unlock on a
  scratch mapping before they are trusted.
- Secure Boot: enrollment model documented (shim+MOK recommended), MOK
  password recorded offline, rollback procedure tested once before any
  custom kernel becomes the default boot entry.

## Lost YubiKey

- Purpose: regain authentication without weakening the PAM stack.
- Path: use the enrolled backup YubiKey (two keys enrolled at all times;
  single-key enrollment is a known gap, not a policy). If no backup key
  exists, boot the distro rescue kernel, authenticate with the LUKS
  recovery passphrase plus the local account password at the console, and
  enroll a replacement key before returning to normal boot.
- What NOT to do: do not add a password-only PAM bypass "temporarily".
  Temporary bypasses become permanent.
- Cost: replacement key purchase and re-enrollment time. Limitation: during
  the window with one key, losing it again means repeating this procedure.
- Recovery path anchor: distro rescue kernel, console authentication.

## Broken PAM

- Symptom: no login path works (SDDM, TTY, sudo all fail).
- Path: boot the distro rescue kernel to a console, authenticate with the
  local account password, inspect `/etc/pam.d/` against the repo's
  versioned copies, restore the known-good files, and test login on a TTY
  before rebooting to normal.
- Prevention: every PAM change is tested on a TTY login in the same
  session it is made, before logging out of the working session. Keep one
  root shell open while editing PAM.
- Limitation: a PAM misconfiguration made remotely with no console access
  is unrecoverable without physical access. Do not edit PAM over SSH
  without a tested rollback.
- Recovery path anchor: distro rescue kernel, local password at console.

## Failed custom kernel (does not boot)

- Path: select the previous known-good kernel (custom or distro) from the
  boot menu. Old working kernels are never auto-deleted, so the fallback
  exists.
- Then: inspect the failure (boot log from the failed entry), fix the
  config, rebuild, and re-test before making it default again.
- Limitation: if the boot menu timeout is zero or the menu is hidden,
  physical access with Shift/Esc at boot is required. Keep a visible boot
  menu with a sane timeout; a hidden menu is a self-inflicted recovery
  blocker.
- Recovery path anchor: previous kernel entry, then the distro kernel.

## Failed kernel signature

- Symptom: Secure Boot refuses the custom kernel (shim/MOK validation
  failure).
- Path: boot the signed distro kernel, verify the signature state
  (`mokutil --sb-state`, `sbverify` on the kernel image), re-sign with the
  enrolled MOK key, and re-test. If the MOK enrollment itself failed, redo
  enrollment with the recorded MOK password before signing.
- What NOT to do: do not disable Secure Boot to "get it working". That
  destroys the anchor the whole architecture rests on.
- Limitation: if the signing key is lost and no backup exists, kernels
  must be re-signed under a newly enrolled MOK; the old signatures are
  unrecoverable. Back up the signing key offline at enrollment time.
- Recovery path anchor: signed distro kernel.

## Secure Boot enrollment failure

- Path: the machine still boots with Secure Boot disabled (its current
  state). Re-run the documented enrollment procedure (shim+MOK) from the
  running system, verify with `mokutil --sb-state`, and only then enable
  enforcement in UEFI.
- Rollback: MOK removal procedure (`mokutil --delete` with the recorded
  password, confirmed at boot) returns to the pre-enrollment state.
- Test the rollback once before any custom kernel becomes default.
- Recovery path anchor: Secure Boot disabled state, which is the known
  starting point.

## Broken UKI (Unified Kernel Image)

- Symptom: the UKI entry fails to boot (bad initramfs embedding, wrong
  command line, signature mismatch).
- Path: boot the distro kernel entry (non-UKI), rebuild the UKI from the
  repo's documented build steps, re-sign, and test the UKI entry before
  making it default.
- Prevention: never replace the only working UKI in place; build the new
  UKI alongside, test-boot it once, then promote it.
- Recovery path anchor: distro kernel entry.

## Lost TPM state / TPM clear

- Consequence: sealed LUKS keys and any TPM-bound secrets are
  unrecoverable. This is by design (a TPM clear is supposed to destroy
  sealed state); the recovery is the offline backup, not the TPM.
- Path: unlock LUKS with the offline recovery passphrase, re-provision
  TPM sealing (new SRK, new sealed policy) from the documented steps, and
  verify unlock works before relying on it.
- What NOT to do: never automate `tpm2_clear`. It is a manual, deliberate,
  witnessed operation with the recovery passphrase in hand first.
- Limitation: any data sealed only to the old TPM state is gone. Keep the
  set of TPM-sealed secrets minimal and documented.
- Recovery path anchor: LUKS recovery passphrase.

## Firmware update changing measurements

- Symptom: after a BIOS/EC or other firmware update, TPM-sealed LUKS
  unlock fails (PCRs changed).
- Path: unlock with the recovery passphrase, re-seal to the new PCR
  values per the documented TPM policy steps, and verify.
- Prevention: record firmware before/after versions for every update
  (never automated flashing); expect PCR changes on any firmware update
  and have the recovery passphrase available before flashing.
- Recovery path anchor: LUKS recovery passphrase.

## LUKS recovery

- Recovery passphrase: recorded offline at setup, verified by a test
  unlock on a scratch mapping. This is the root of all storage recovery.
- Header backup: `cryptsetup luksHeaderBackup` stored offline, separate
  from the passphrase. Restores from header corruption.
  Restore: `cryptsetup luksHeaderRestore` from rescue boot, then unlock
  with the passphrase and verify the filesystem before mounting read-
  write.
- What NOT to do: do not store the header backup on the encrypted volume
  it describes. That is a locked-box-inside-the-locked-box.
- Limitation: header backup plus passphrase recover the volume; they do
  not recover a forgotten passphrase. There is no backdoor.
- Recovery path anchor: offline passphrase + offline header backup.

## NVMe password loss

- Note: the NVMe pre-boot password (if ever set in Lenovo BIOS) is
  separate from LUKS. If set and lost, the drive is cryptographically
  inaccessible; there is no vendor backdoor worth relying on.
- Policy: do not set an NVMe pre-boot password unless there is a written
  reason LUKS2 alone is insufficient, and if set, record it with the same
  offline discipline as the LUKS recovery passphrase.
- Recovery path anchor: the recorded password, or drive replacement if
  truly lost. Prevention beats recovery here.

## Failed display config

- Symptom: black screen or wrong mode after a display change.
- Path: switch to a TTY (Ctrl+Alt+F3), revert the compositor/display
  setting, and restart the session. If the TTY is also unusable, boot the
  distro kernel (which uses known-good display defaults) and revert from
  there.
- The 24-bit-scanout FBC experiment (docs/DISPLAY_POWER.md) reverts by
  re-enabling 30-bit scanout; no persistent change is made by the test.
- Recovery path anchor: TTY, then distro kernel.

## Broken network driver (only USB Wi-Fi exists)

- Reality: the external MT7921U (0e8d:7961) is the ONLY network path. No
  wired NIC is confirmed, no internal Wi-Fi is confirmed. A driver
  regression means no network, full stop.
- Path: keep a known-good USB Wi-Fi adapter (a second, tested unit, ideally
  a different chipset with an in-tree driver) physically available as the
  fallback. If the MT7921U driver breaks after a kernel update, boot the
  previous known-good kernel (kept per policy) and investigate from there.
- Prevention: never make a new kernel the default before the Wi-Fi path
  is tested on it. The suspend test matrix (docs/SUSPEND.md) covers the
  resume path explicitly.
- Limitation: without the fallback adapter and without a working previous
  kernel, recovery requires physical media (USB stick with packages).
  Keep both.
- Recovery path anchor: previous kernel + fallback adapter.

## Failed suspend

- See docs/SUSPEND.md. Short version: force off, boot, read
  `journalctl -b -1`, identify the subsystem, apply the documented
  workaround, re-test. Never "fix" suspend by disabling it.

## Broken AppArmor profile

- Symptom: service or VM fails to start with denials; or worse, something
  was set to complain mode and forgotten.
- Path: read the denial in the audit log, fix the profile (add the least
  privilege needed), reload, re-test in enforce mode. `aa-status` must show
  enforce, not complain, when done.
- What NOT to do: do not leave profiles in complain mode as a permanent
  fix, and do not disable AppArmor to get a VM booting.
- Recovery path anchor: distro defaults for the profile, then re-apply the
  repo's hardening.

## Corrupted initramfs

- Symptom: boot fails early (cannot find root, missing modules).
- Path: boot the distro kernel (its initramfs is intact), chroot or boot
  into the system, regenerate the initramfs (`update-initramfs -u -k
  <version>`), and verify before rebooting.
- Prevention: after every initramfs regeneration, keep the previous
  initramfs alongside until the new one has booted successfully once.
- Recovery path anchor: distro kernel, then previous initramfs.

## Universal fallback

If every path above fails: boot the signed DISTRO rescue kernel (or
Ubuntu install media, verifying its signature), authenticate with the
LUKS recovery passphrase and local credentials, and rebuild from the
repo's versioned configuration. The repo is the system documentation;
a machine rebuilt from it plus the offline secrets is the definition of
recovered.

## What is NOT in this plan

- No emergency bypass users, no passwordless rescue accounts, no
  single-user-mode root shells without authentication. If a recovery path
  needs authentication the operator does not have, that path is correctly
  closed; the offline secrets are the way in.
