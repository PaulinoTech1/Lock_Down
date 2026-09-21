# Storage Security

## LUKS2 as the OS-controlled encryption boundary

LUKS2 full-disk encryption is the encryption boundary this project controls and verifies. The chain is:

firmware NVMe authentication (OPTIONAL, if configured; see docs/NVME_SECURITY.md)
  -> Secure Boot (docs/SECURE_BOOT.md; currently disabled, Phase C pending)
    -> signed kernel
      -> LUKS2 unlock (TPM2+PIN or recovery passphrase; docs/TPM.md)
        -> Linux userspace

Purpose: data at rest is unreadable without the keys. Every layer above LUKS2 (Secure Boot, signed kernel, TPM sealing) exists to protect the conditions under which LUKS2 unlocks; none of them replaces LUKS2. If a layer is missing or disabled (as Secure Boot currently is), LUKS2 still holds: the disk is still encrypted, and the passphrase/PIN is still required.

Cost: KDF computation at unlock (Argon2id tuning below), header backup discipline, keyslot management on every change. Limitation: LUKS2 protects data at rest. It does not protect a running, unlocked system against runtime compromise, cold-boot memory extraction of the in-RAM master key, or an attacker who observes the passphrase/PIN. Recovery path: header backup + offline recovery passphrase (below).

## Argon2id KDF guidance

LUKS2 defaults to Argon2id, which is the correct choice; do not switch to PBKDF2 without a documented reason.

- For the recovery passphrase keyslot: use LUKS2 defaults or harder. `cryptsetup luksFormat --type luks2 --pbkdf argon2id` with explicit `--pbkdf-memory`, `--pbkdf-parallelism`, and `--pbkdf-force-iterations` only if you have measured the unlock-time tradeoff on this machine (i5-1245U, 15W envelope; heavy KDF parameters cost seconds at every boot and resume-from-hibernation, though this machine uses s2idle, not hibernation).
- For the TPM2-bound keyslot: the KDF cost matters less because the TPM releases the key without passphrase KDF on the normal path, but keep Argon2id for consistency; the recovery passphrase path still pays the KDF cost, which is acceptable.
- Never weaken KDF parameters to speed up boot without recording the decision and rationale. Unlock latency is a usability cost, not a security justification for weakening the KDF.

Confidence: Medium that LUKS2 defaults are appropriate here; the exact iteration/memory numbers should be chosen at format time based on measured unlock latency on this CPU, not copied from a guide.

## Header backup procedure

The LUKS header contains the keyslot metadata; without it, the encrypted data is unrecoverable even with the correct passphrase. Back it up:

1. `cryptsetup luksHeaderBackup <device> --header-backup-file <offline-path>/luks-header-<date>.img`
2. Store the backup on offline encrypted media, separate from the recovery passphrase storage (two different media or two different encrypted containers; losing both together must require two independent failures).
3. Re-take the backup after every keyslot change (add/remove/w change, TPM re-seal). A stale header backup restores stale keyslots.
4. Test restore procedure on a scratch copy, never on the live device, before trusting the backup.

What the header backup does NOT contain: it does not contain passphrases or the master key in usable form without the keyslot passwords. It is sensitive but not sufficient alone to decrypt.

## Recovery passphrase handling

- The recovery passphrase is long, random, and generated (not chosen). It lives in its own LUKS keyslot.
- Storage: offline encrypted media, plus optionally a sealed paper copy in a physically secure location. Never on the machine, never in this repo, never in cloud notes, never in a password manager vault that syncs to this same machine as its only copy (the vault on the encrypted disk is fine as a convenience copy; the offline copy is the recovery one).
- Test it: boot from it after every re-seal and after every keyslot change. An untested recovery passphrase is an aspiration, not a control.
- Rotation: rotate if it was ever typed on an untrusted machine, photographed, or handled by anyone outside the trust boundary.

## Keyslot management

- `cryptsetup luksDump <device>`: audit keyslots before and after every change. Know which slot is the recovery passphrase, which is the TPM2 token, and that no unexpected slots exist.
- Adding a slot: `cryptsetup luksAddKey`. Removing: `cryptsetup luksRemoveKey` or `luksKillSlot` (slot numbers from luksDump; double-check before killing).
- systemd-cryptenroll TPM operations manage their own slot; verify with luksDump afterward (see docs/TPM.md for the wipe-slot warning: wiping the wrong slot is the unrecoverable mistake).
- Never leave a weak or temporary passphrase in a slot "for now". Temporary credentials become permanent.

## What happens on drive removal / offline access

If the NVMe drive is removed from the machine and attached elsewhere (another machine, a USB enclosure, forensic write-blocker):

- The data remains encrypted. LUKS2 does not depend on the TPM of the original machine for the passphrase path; it depends on the passphrase, which the attacker does not have.
- The TPM2-bound keyslot is useless off the original machine: the TPM that seals it is soldered to the original board, and PCR policy will not match on different hardware anyway.
- Brute force against Argon2id with a strong random passphrase is infeasible; against a weak human passphrase it is the expected attack. This is why the recovery passphrase is generated, not chosen.
- The LUKS header (first megabytes) is readable and identifies the volume as LUKS; this leaks volume existence and KDF parameters, not data.

## Re-encryption notes

- `cryptsetup reencrypt` can change the master key or encryption parameters online, but it is slow on 1TB and carries interruption risk. Prefer it only when there is a reason (suspected key compromise, algorithm migration).
- Re-encryption requires a current header backup first, uninterrupted power (AC connected, battery thresholds respected), and no suspend during the operation (s2idle during reencrypt is a data-loss risk; disable suspend for the duration).
- After re-encryption, re-take the header backup and re-test the recovery passphrase. The old header backup is stale the moment re-encryption completes.

## Destructive operations: documented, never automated

The following are documented for completeness. None of them are scripted anywhere in this project, and none may be run without explicit, deliberate admin intent with backups verified first:

- `cryptsetup luksErase`: destroys all keyslots. Data becomes permanently unrecoverable. There is no undo.
- `cryptsetup luksHeaderRestore` with a wrong or stale file: can destroy current keyslots.
- NVMe-level destructive operations (sanitize, format, secure erase, PSID revert): see docs/NVME_SECURITY.md. These operate below LUKS and destroy everything including the header.

Rule: if a command's man page says the data cannot be recovered, it does not go in a script.
