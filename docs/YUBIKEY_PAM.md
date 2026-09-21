# YubiKey FIDO2/U2F via pam_u2f

Purpose: require local password plus YubiKey physical presence (user presence check) for privileged local authentication, so a compromised password alone is not enough to get root or unlock the screen. This uses FIDO2/U2F through `pam_u2f`. It does NOT use Yubico OTP, which would depend on Yubico's cloud service and is out of scope for this workstation.

Status: RECOMMENDED. Confidence: High that the mechanism works on Ubuntu LTS; Medium that the exact PAM filenames ship identically on the target release until verified on the machine.

## Scope

Applied to exactly four services:

- `sudo`
- `login` (TTY login)
- `sddm` (KDE display manager)
- KDE screen unlock (on Ubuntu this is handled through the PAM stack the locker uses; verify which service name the installed KDE version uses, commonly `kde` or the screen-locker config, and apply the same pattern)

## Prerequisites

- `libpam-u2f` installed. Verify with `dpkg -l libpam-u2f` and confirm the module exists at `/usr/lib/x86_64-linux-gnu/security/pam_u2f.so`.
- The YubiKey is enrolled and reachable over USB (check USB policy so the key is not blocked).
- The user mapping file lives at `/etc/u2f_mappings` (system-wide, outside any encrypted home, so it is readable at login time). It must be root-owned with 0600 permissions.

## Auth lines

Add the pam_u2f line in the `auth` stack so that password stays required AND the key is required. The ordering must be:

```text
# pam_u2f: YubiKey second factor. Keep pam_unix first so password stays required.
auth required pam_unix.so
auth required pam_u2f.so cue userpresence authfile=/etc/u2f_mappings
```

Rules for these lines:

- `required`, not `sufficient`. A `sufficient` pam_u2f line can let the YubiKey alone satisfy auth, or conversely let pam_unix alone satisfy auth if ordered first; both outcomes weaken the two-factor intent. `required` forces BOTH to succeed.
- No `nouserok`. `nouserok` would let users without a mapping entry skip the key entirely, silently downgrading to password-only. Omit it so an unregistered user fails closed (denied) rather than falling back to password-only.
- `cue` so the user gets a prompt to touch the key instead of a silent hang.
- `userpresence` (short form `up`) requests the physical touch, not just device presence.
- `authfile=/etc/u2f_mappings` keeps the mapping out of the encrypted home. If the mapping lived under `~/.config/Yubico/u2f_keys`, it would be unavailable before the home directory is decrypted/unlocked, and the ordering would break.
- Keep `pam_unix.so` required as well. Both modules must be `required`, which makes this a genuine AND of password and key.

## Mapping file

Format (comma-separated, one line per user):

```text
<username>,<keyHandle>,<coseKey>,<coseType>,<transports>
```

Fill `<username>` with the actual local username at enrollment time. Generate entries with:

```text
pamu2fcfg -u <username> -N > /etc/u2f_mappings
```

`-N` avoids PIN and keeps the factor as presence (touch) only. Then `chown root:root /etc/u2f_mappings && chmod 0600 /etc/u2f_mappings`.

Note: with `nouserok` omitted, a user with no line in the file is DENIED by these services. That is the intended fail-closed behavior. Verify after deployment that every user who needs these services has a mapping line.

## Safe deployment workflow

This is the procedure. Do not deviate from it, and do not script the PAM edits blindly.

1. Open a working root shell (a live root terminal) and KEEP IT OPEN for the whole procedure. This is the recovery path if a PAM edit locks you out. Do not close it until all services are tested.
2. Back up each PAM file before touching it: `cp -a /etc/pam.d/<service> /etc/pam.d/<service>.bak.<date>`.
3. Apply the change to ONE service at a time, in this order: `sudo`, then `login`, then `sddm`, then the screen unlocker.
4. Test positive auth on that service (correct password + key touch succeeds).
5. Test auth WITHOUT the YubiKey present (must FAIL).
6. Test WRONG password + YubiKey present (must FAIL).
7. Only after all three tests pass for a service, move to the next service.
8. Run `scripts/audit-pam-u2f.sh` after each service change and again at the end.

## Second key

Register a second YubiKey in the same mapping file (append its line) and store that key OFFLINE in a physically separate, secure location. If the primary key is lost or destroyed, the backup key is the fastest recovery. Test the backup key at least once after enrollment.

## Lost-YubiKey recovery

If both the primary and backup keys are unavailable:

1. Use the open root shell (if still available) or boot the rescue path to disable the pam_u2f lines or add a temporary mapping.
2. The distro rescue kernel and a Live USB are the recovery paths; they are unaffected by PAM policy on the disk. See docs/APPARMOR.md recovery notes for the same principle.
3. Restore from the per-file backups: `cp -a /etc/pam.d/<service>.bak.<date> /etc/pam.d/<service>` and re-run the audit script to confirm state.
4. Re-enroll keys and re-apply per the deployment workflow above.

Prevention is better than this procedure: keep the second key registered and stored offline before you ever need it.

## Forbidden

Never run or ship a script that blindly overwrites `/etc/pam.d/*`. PAM mistakes lock out every privileged path at once. Every PAM change on this machine is: one file at a time, backed up first, tested positive and negative before moving on, with a live root shell open throughout.

## Limitation

- pam_u2f enforces possession + touch, not PIN. Someone with physical access to the logged-in unlocked session gains nothing extra from this control; it protects authentication events only.
- Touch-only U2F does not bind the session to the key after auth; the session is as strong as the rest of the system once granted.
- This does not replace FIDO2 SSH keys or WebAuthn for remote services; it covers local PAM services only.

## Cost

One extra touch per sudo/login/unlock. Lost-key risk is real and is handled by the second-key recommendation and the recovery procedure above.
