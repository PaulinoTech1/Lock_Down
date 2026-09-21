# Contributing

This is a personal, single-hardware project, but contributions are welcome if
they respect the constraints below. The project targets exactly one machine
(see `SECURITY.md`); contributions that assume other hardware will be rejected.

## Commit conventions

Logical commits, one concern per commit. Every commit message starts with one
of these prefixes:

- `docs:` documentation, runbooks, diagrams, threat model updates
- `kernel:` kernel config changes, patches, build definitions
- `security:` AppArmor profiles, nftables rules, sysctl, USBGuard, PAM, LSM policy
- `auth:` authentication changes (pam_u2f, LUKS/TPM policy, key handling docs)
- `virt:` KVM/libvirt, VM profiles, sVirt confinement
- `power:` suspend/resume, pstate/HWP tuning, battery thresholds, benchmarks
- `scripts:` helper scripts, validators, install tooling
- `ci:` CI workflow and automated checks

Example: `kernel: drop amdgpu and nouveau from the hardened profile`.

Keep the subject under 72 characters. Explain the why in the body: what
hardware fact or threat-model item drives the change, and what validation was
run. A kernel config change without a stated hardware justification is not
mergeable.

## No secrets in commits

Never commit: Secure Boot or MOK private keys, LUKS keys or recovery
passphrases, TPM secrets, SSH private keys, passwords, firmware passwords, disk
passwords, or any credential. The `.gitignore` covers the known patterns, but
the rule is semantic, not syntactic: if it authenticates, decrypts, or signs,
it does not go in git. See `docs/SECRETS.md` for where each secret lives
instead and how to check for accidental commits.

Before pushing, run the secret scan the repo provides (see `docs/SECRETS.md`).
If a secret ever lands in history, say so immediately; the remediation is
rotation of the exposed material plus history surgery, not just a revert.

## Hardware tests labeled local

Any test that requires the physical machine (suspend/resume matrix, Wi-Fi
recovery, USB authorization, TPM sealing, Secure Boot enrollment, benchmarks)
must be labeled `local` in its name or metadata and must be skipped in CI. CI
runs static checks only: config sanity, shellcheck, profile syntax, doc link
checks. A test that only passes on the maintainer's laptop is honest when it
says so.

## PR expectations

- One concern per PR, matching the commit prefix scheme above.
- Describe: what changed, what hardware fact or threat-model entry justifies it,
  what validation was run (and on which kernel: hardened, diagnostic, or distro
  rescue), and the recovery path if the change misbehaves.
- Kernel config PRs must state the before/after for affected subsystems and
  confirm the rescue kernel entry still boots.
- Security control PRs must state purpose, cost, limitation, and recovery path
  (the README standard). "This makes the system secure" is not an acceptable
  description; say what attack surface it reduces and under what assumptions.
- Docs PRs that change a VERIFIED hardware fact must cite the runtime evidence
  (command and output date). UNVERIFIED stays UNVERIFIED until checked.
- No marketing language. No em dashes in docs (house style: hyphens or commas).
