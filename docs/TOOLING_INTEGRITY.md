# Kernel tooling integrity

These helpers prepare and check artifacts. They do not establish a successful
boot, hardware validation, or reproducible builds. Audit10's historical files
and configuration are unchanged. The physical owner still controls acceptance,
signing, installation and promotion.

## Provenance and fresh builds

`scripts/build-kernel.sh` now requires all provenance inputs explicitly. It no
longer downloads an example release, defaults to the running kernel config, or
reuses `build/linux-*`. Existing directories are never deleted. Each invocation
uses a new private `build/audited.*` workspace; failed workspaces are retained
for inspection. The repository must be clean. Build as an ordinary user in a
trusted Linux environment, not as root or in a shared writable checkout.

Required options:

| Option | Meaning |
| --- | --- |
| `--version` | Exact upstream numeric point release |
| `--localversion` | Exact reviewed suffix, including leading hyphen |
| `--archive` | Local `linux-VERSION.tar.xz` |
| `--sha256` | Independently reviewed SHA-256 of that compressed archive |
| `--signature` | Detached signature of the uncompressed tar |
| `--keyring` | Exported OpenPGP public keyring containing the reviewed signer |
| `--fingerprint` | Full actual signing-key fingerprint, not user ID or short key ID |
| `--base-config` | Explicit complete starting config |
| `--firmware-dropin` | Reviewed drop-in scoped to the expected exact release |
| `--profile` | `hardened` (default) or `diagnostic` |
| `--dry-run` | Validate invocation inputs and describe work; does not authenticate or build |

No release fingerprint is hard-coded or automatically fetched. Review the
signer's identity and revocation/expiry state through trusted channels before
supplying the public keyring and fingerprint. A signing subkey must be pinned
by its own fingerprint. An old local keyring cannot prove current revocation
freshness. Kernel.org specifies verification of the **uncompressed tar**, and
publishes developer-key guidance; archive hashes do not replace developer
signatures. See [kernel.org signature guidance](https://www.kernel.org/signature.html).

`verify-kernel-source.sh` accepts the same version/archive/digest/signature/
keyring/fingerprint/localversion inputs plus `--config` and `--source-dir`.
The destination must be a nonexistent absolute `linux-VERSION` path under a
safe existing directory. Even an apparently pristine existing tree is refused.
This is deliberate freshness enforcement, not an in-place tree repair tool.

The helper snapshots inputs privately, checks the archive digest, verifies GPG
exit status and machine-readable signature status, rejects expired/revoked/error
statuses and requires exactly one matching VALIDSIG. Only then does it inspect
and extract the archive. Special files, hardlinks, paths outside the expected root,
and recognized generated artifacts are refused. Regular files are extracted
before any symlink is created; relative symlinks are then checked to resolve
inside the source tree, including after all links have been created. Unusual
member names outside the supported safe character set are refused. The authenticated source is
then queried with `make kernelversion`; there is no compilation in that helper.
Read the retained `gpg.log` for diagnostics. Do not weaken verification merely
to make a release archive pass.

No patch series is silently accepted. `--patch-manifest` returns UNKNOWN/nonzero;
support for reviewed patches requires a separate design. Tree identity in the
manifest means a fresh extraction of the authenticated archive, not a claim
that source cannot subsequently be modified by its owner.

The build wrapper copies inputs/fragments into its private workspace, checks
fragment LOCALVERSION and firmware syntax/release guard, merges config, runs
olddefconfig and queries kernelrelease. Exact release, required symbols and
production security gates must pass before compilation. Module support remains
disabled. After compilation it checks config/release stability and uses
`verify-build-packages.sh` to compare the package's config and inner image
byte-for-byte with the resolved config and compiled bzImage. It requires exactly
one matching image package and rejects module payloads. Package extraction does
not execute maintainer scripts.

The wrapper clears common make/source/output/architecture/tool overrides, but
this is not a hermetic sandbox. PATH, compiler executables, host libraries, the
OS, build-account integrity and intentional source code execution remain trusted.
Production builds must run on the intended Linux build host. None was run for
this tooling change. Diagnostic capability resolution remains a separate task;
this change does not fix or claim diagnostic BTF availability.

## Build manifest

On a successful build, `manifest.json` is emitted only after the checks above,
using `write-build-manifest.sh`. Schema: `lockdown.build-provenance.v1`.

It records version/release/localversion, archive filename/hash, actual pinned
signer fingerprint, archive-derived source identity, requested and resolved
config hashes, firmware hash, repository commit, compiler/version, binutils
version, UTC timestamp, and each package filename/SHA-256. Requested config is
the merge result before olddefconfig, not the original base config. The copied
base and fragments remain in the workspace for inspection.

`patch_series_sha256` is null with NOT_APPLICABLE status for the supported pristine
path. `signed_inner_image_sha256` is null with UNKNOWN_NOT_SIGNED_BY_BUILD status:
builds do not sign. A later owner signing/package acceptance workflow must record
the signed image and repacked package hashes separately; never silently overwrite
an unsigned-package digest with a signed-package digest.

The serializer uses fixed field order and argument order. `BUILD_TIMESTAMP` can
be supplied for deterministic fixture output; otherwise UTC now is recorded.
The standalone serializer records supplied metadata and file hashes; it does not
authenticate those claims. The wrapper is responsible for validation first.
A manifest is not a signature, trust certificate, or reproducibility certificate.

## Verification results

`verify-secure-boot.sh` uses these aggregate statuses:

| Exit | Meaning |
| --- | --- |
| 0 | All required checks passed or are explicitly NOT_APPLICABLE |
| 1 | At least one FAIL; takes precedence over UNKNOWN |
| 2 | Invalid invocation |
| 3 | Required evidence UNKNOWN/incomplete |

Required evidence: enabled Secure Boot, selected integrity/confidentiality
lockdown, matching `EXPECTED_KERNEL`, and known module policy. Missing expected
release is UNKNOWN. Disabled Secure Boot is FAIL for this profile. Raw dmesg and
EFI inventories are informational; a matching log substring is never PASS.
Module-signature enforcement is NOT_APPLICABLE when the config is monolithic.
For modular configs, this check requires MODULE_SIG_FORCE; it does not execute
unsigned-module load tests or verify individual module signatures.

`BOOT_EVIDENCE_ROOT` redirects filesystem reads to offline evidence for fixture
testing, explicitly labeled in output. Test commands also replace external
queries with command doubles. Offline results must not be labeled live checks.

`verify-module-signatures.sh` inventories marker presence and parseable metadata
separately. Neither establishes a cryptographically trusted signer. It returns
3 for unresolved trust, 1 for an unsigned raw module, and 0 only for monolithic
NOT_APPLICABLE. A failed loaded-module enumeration cannot become an empty passing
list. Compressed `.ko.xz`, `.ko.zst` and `.ko.gz` are identified; metadata readers
may support them, but cryptographic verification remains UNKNOWN.

## Signing safety

The existing external key/certificate model is unchanged. No enrollment occurs.
The image helper requires `--expected-sha256` in addition to key, certificate
and image. It rejects in-repository signing inputs, symlink/hard-linked images,
unsafe path ancestors, and changed input hashes. It signs a private snapshot
into a private sibling directory, verifies with `sbverify --cert` against a
snapshot of the supplied certificate, then checks the original identity/hash
again before atomic replacement. A predictable `IMAGE.signed` path is never used.
The existing-signature check reads `sbverify --list` output: that command can
return success while reporting `No signature table present`. An actual listed
signature requires `--force`; unrecognized output stops with UNKNOWN.

`--modules-dir` remains optional for monolithic callers. If it contains any
`.ko*` artifact, including compressed modules or symlinks, the helper returns
UNKNOWN/3 before signing anything. This intentionally removes the old unsafe
marker-only modular-signing behavior. A full modular crypto workflow is outside
scope and must be designed before modular signing can resume.

Successful image verification proves the supplied certificate verifies the
image, not that the certificate is enrolled in MOK, the key is secure, or an
outer Debian package contains that image. Existing signed images still require
`--force`. Do not use this helper to mutate installed boot files during tests.
Private staging protects against other unprivileged users under POSIX ownership
and mode assumptions; it does not defend against root, the same compromised
account, hostile tool binaries, or hostile filesystem/ACL semantics.

## Suspend diagnostics

Default operation only collects limited state. It creates a private random
directory with umask 077. `SUSPEND_DIAG_DIR`, if supplied, is an existing absolute
safe **parent**, not a reused output directory. Symlinks, unexpected ownership
and writable ancestors are refused; root-owned sticky ancestors such as /tmp
are allowed for private children. Raw dmesg is omitted because it may contain
identifiers or secrets. No MAC, SSID, serial or credential collection was added.

`--check` reads mem_sleep without writing power state: selected `[s2idle]`
returns 0, another default returns 1, unreadable evidence returns 3. The actual
`--do-suspend` path requires that same preflight and typed confirmation.
`SUSPEND_EVIDENCE_ROOT` supports offline fixture collection/checks and is rejected
with `--do-suspend`. This assignment never ran the suspend path.

## CI and tests

`config/current-candidate.txt` is parsed as data, never sourced. It selects the
current static policy target, not a production promotion. Review changes to its
config, firmware and release together. `check-current-candidate.sh` runs all
seven existing gates only against that target, leaving historical failed configs
intact. Historical audit8/9/10 gates express retained invariants; future policy
changes must consciously revise the gate list.

Duplicate checking counts both assignments and disabled-comment entries.
Safety scanning reports filenames/rules rather than secret-like matched text.
It is a bounded regex check, not complete secret detection or a shell parser.
CI includes skill scripts in syntax/ShellCheck and uses only read permissions.

Run `bash tests/run-tooling-tests.sh` for behavioral fixtures and
`bash scripts/check-current-candidate.sh` for current policy. CI sets
`REQUIRE_CRYPTO=1`: missing real crypto tools fail rather than skip. Integration
tests generate disposable keys and a tiny non-booted PE fixture, verify expected
and wrong certificates, and authenticate a signed synthetic source tarball.
They do not compile or boot Linux. The existing live KVM smoke test is deliberately
excluded from the static runner, even if /dev/kvm happens to exist.

## Before/after and evidence record

Test-first cycles recorded failing fixtures for missing helpers/options, missing
monolithic status, and the expired-status regression reaching make. Linux-only
symlink and real-crypto cases are prepared but were not executable locally.
Expected negative-case FAIL output inside a passing suite is not a failing suite.

| Area | Before | After | Test evidence | Residual risk |
| --- | --- | --- | --- | --- |
| Source | Manual verification, existing tree reused | Explicit digest/signature/fingerprint and new destination; invalid/expired state rejected before make | Synthetic archive, wrong version/hash/signer/status, stale/dirty tree and LOCALVERSION fixtures | Real release archive acceptance and current signer/keyring freshness require Linux/owner review |
| Build identity | Release/package identity largely manual | Exact config/release and package/config/image comparison; provenance JSON | Wrong release, config/image mismatch, missing package and deterministic manifest fixtures | Actual kernel compilation not performed; toolchain/host remain trusted |
| Secure Boot | Printed FAIL could return success | Aggregated FAIL/UNKNOWN/N/A; logs informational | Ten command-fixture cases | Real firmware/boot policy not tested from Windows |
| Signing/modules | Replaced before verification; marker treated as verification | Private staged verification before replacement; unresolved module trust fails closed | Mock signing-order, original-preservation, hash, module/compressed-form fixtures; real crypto test provided | Real sbsigntools integration pending Linux execution; MOK enrollment not established |
| Diagnostics | Predictable output, selected mode could differ | Private output, ancestor checks, explicit s2idle preflight | Offline collection/default/missing-mode fixtures | POSIX permission/symlink tests must run on Linux; no suspend performed |
| CI | Two tests and assignment-only duplicates | Current candidate gates, behavioral negative fixtures, redacted scans, required crypto integration | Static policy negative fixtures and passing Linux Actions run | Static checks do not validate hardware; regex scans are incomplete by design |

Windows limits: Git Bash fixture execution is available. ShellCheck, make,
objcopy, sbsign and sbverify were not found locally; WSL enumeration returned no
installed distribution. Real symlink semantics were unavailable in Git Bash.
The local crypto integration test explicitly skipped at missing make. GPG and
OpenSSL are present, but that does not establish the combined Linux integration
test. CI installs already-required build/signing/static-check tools. No
dependency was added to the production runtime.

Local final checks: shell syntax passed for scripts, tests and skill helpers;
documentation relative links and bounded safety scanning passed; sysctl parsing
passed for 30 keys. nftables syntax explicitly skipped because nft is absent.
Current candidate gates passed: preflight 83/0/0, boot-critical 82/0/0, security
26 checks, config audit zero required failures, and audit8/9/10 gates PASS.
All available local tooling command-fixture suites passed. Those local results
did not establish ShellCheck, real cryptographic integration or POSIX symlink
coverage. No Linux kernel build or hardware validation was performed.

The first published GitHub Actions run reached the disposable cryptographic
fixture and exposed the unsigned-image `sbverify --list` exit-status behavior.
The follow-up fixture covers unsigned, signed and unknown list output, and the
repository pins LF checkout for shell and configuration files on Windows.
The [follow-up Linux Actions run](https://github.com/PaulinoTech1/Lock_Down/actions/runs/36630031590)
at `20c187b` passed ShellCheck, current candidate policy, bounded safety checks,
all behavioral fixtures including disposable GPG/PE signing integration,
userspace file checks and relative-link validation. It did not build or boot a
kernel, sign with owner keys or validate the physical ThinkPad.

No audit11 configuration was generated. Frozen audit10 config, firmware,
runbook, package hashes and evidence were not edited. No owner keys, recovery
secrets, host boot configuration, firmware, TPM, GRUB or physical hardware were
used or changed.
