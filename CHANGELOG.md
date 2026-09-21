# Changelog

All notable changes to this project are recorded here. Dates are in the
America/New_York timezone of the maintainer.

## [0.1.0] - 2026-09-21

Initial project structure.

- Added project documentation set: `README.md`, `SECURITY.md`, `LICENSE`,
  `CONTRIBUTING.md`, and this changelog.
- Added `docs/ARCHITECTURE.md`: full boot chain, the three boot paths
  (hardened custom, diagnostic custom, distro rescue), per-layer trust roots,
  and the defense-in-depth rationale.
- Added `docs/THREAT_MODEL.md`: in-scope, partially-addressed, and out-of-scope
  threats, including the Setup-Mode evil-maid implication while Secure Boot
  remains unenrolled.
- Added `docs/HARDWARE.md`: resolved hardware state as of 2026-09-21 with
  VERIFIED / UNVERIFIED / RECOMMENDED / OPTIONAL / EXPERIMENTAL labels, serials
  redacted, and the config decision each section drives.
- Added `docs/RUNTIME_VERIFICATION.md`: dated log of the laptop-side answers
  received 2026-09-21 and the remaining open items.
- Added `docs/SECRETS.md`: what must never be committed, where each secret
  lives instead, and how to check for accidental commits.
- Added `.gitignore` covering Secure Boot/MOK private keys, LUKS/TPM/SSH key
  material, passwords, build artifacts, and logs.
- Created directory scaffolding: `config/`, `scripts/`, `sysctl/`, `apparmor/`,
  `nftables/`, `usbguard/`, `power/`, `vm-profiles/`, `tests/`,
  `.github/workflows/`.

No kernel configs, build scripts, or install automation exist yet; those arrive
in later phases. Nothing in this release should be treated as production-ready.
