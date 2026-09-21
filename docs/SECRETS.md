# Secrets Handling

The rule is semantic, not syntactic: if it authenticates, decrypts, or signs,
it does not go in git. The `.gitignore` covers the known filename patterns,
but a new secret with a new filename is still a secret. Read this file before
generating any credential for this project.

## What must never be committed, and why

- **Secure Boot / MOK private keys** (`*.pem`, `*.key`, `MOK.priv`, `*.p12`,
  `*.pfx`). Why: anyone with the private half can sign a kernel your machine
  will boot. Compromise means re-enrollment of the entire boot trust chain.
- **LUKS keys, key files, and recovery passphrases.** Why: they decrypt the
  disk directly, bypassing TPM+PIN entirely. A committed recovery passphrase
  is a committed disk.
- **TPM sealed blobs and TPM secrets.** Why: they are bound to this TPM, but
  publishing them invites offline analysis and confuses incident response.
- **SSH private keys** (`id_rsa`, `id_ed25519`, `*_sk`, and friends). Why:
  they authenticate as you to every host that trusts the public half.
- **Passwords, PINs, firmware passwords, disk passwords.** Why: obvious, but
  people commit them in "temporary" notes. There are no temporary commits.
- **YubiKey / FIDO2 / PIV private material and enrollment secrets.** Why: the
  credential is the authentication. The public halves and `pam_u2f` auth
  mappings without secrets are fine; anything that could mint an assertion is
  not.
- **GPG, age, minisign private keys.** Why: they sign releases and encrypt
  backups. Same reasoning as Secure Boot keys.

## Where each secret lives instead

- **Secure Boot / MOK private keys:** generated on an offline machine (or at
  minimum an air-gapped live session), stored on encrypted offline media
  (LUKS-encrypted USB) kept separate from the laptop. Two copies in two
  locations is RECOMMENDED. Never on the laptop's own disk unencrypted, never
  in the repo, never in backups that leave your control unencrypted.
- **LUKS recovery passphrase:** written on paper and/or stored on encrypted
  offline media, recorded BEFORE TPM sealing is configured (Phase 7). Paper
  lives somewhere a burglar and a fire do not both reach. This is the one
  secret that must exist before the control that depends on it.
- **YubiKey credentials:** on the keys themselves (they are designed not to
  export private material). Enrollment data (which key, which slot, backup
  key identity) can be documented; the credential cannot leave the key.
- **MOK private key:** same handling as Secure Boot keys: encrypted offline
  media, never in git, never on the daily-driver filesystem.
- **TPM-sealed state:** in the TPM. No automated TPM operations, no scripted
  clears, no committed blobs. If you must export anything for migration,
  treat the export as a secret with the same handling as a LUKS key.
- **Firmware (supervisor) password:** memorized or in the owner's password
  manager. Never in the repo, never in shell history (use the UEFI UI or a
  prompt that does not echo).
- **SSH keys for the machine:** generated on the machine, private half stays
  on the machine with 0600 permissions. SSH is disabled by default anyway;
  if enabled later, keys never transit through the repo.

## How to check for accidental commits

Run these before every push, and in CI on every PR:

1. **Pattern scan.** `git grep -nEi 'password|passwd|secret|private[_-]?key|recovery|passphrase|BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' -- ':!docs/SECRETS.md' ':!CHANGELOG.md'` and read every hit. Docs mention these words legitimately; key material does not look like prose.
2. **Entropy scan.** Run a secret scanner (e.g. gitleaks or trufflehog) against
   the diff and, periodically, full history. A scanner is a backstop, not a
   proof: it misses novel formats and flags noise.
3. **Staged review.** `git diff --cached --stat` and actually read the staged
   files. Most accidental commits are caught here by a human who looks.
4. **Filename audit.** `git ls-files | grep -Ei '\.(pem|key|p12|pfx)$'` should
   return nothing except possibly public halves (`.pub`, `.der`, `.cer`),
   which are safe.

## If a secret lands in history

1. Treat it as compromised the moment it is pushed anywhere other people (or
   backups, or CI logs) can see. Rotate or revoke it: new MOK and
   re-enrollment for signing keys, new LUKS passphrase and re-seal for disk
   keys, new SSH keys, new firmware password.
2. Then do history surgery (filter-repo or a fresh history) so the secret is
   not sitting in the repo for the next clone. A revert commit does not
   remove the secret from history.
3. Record the incident in the changelog honestly: what was exposed, what was
   rotated, what changed in procedure. Secrets incidents are how the checklist
   above gets better.

Prevention beats rotation: generate secrets offline, name files so the
`.gitignore` catches them, and never paste a credential into a file under
version control "just for now".
