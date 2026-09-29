# Tooling integrity implementation plan

Baseline: windows-codex at 78ff2a7814280bae74ba93b39656f4a42e92ce97,
clean before implementation. Frozen audit10 files match 4dfd9e1.

Scope: tooling only. No real build, signing with owner keys, installation,
boot, suspend, TPM, firmware, kernel configuration, or recovery-policy change.

1. Test and fix Secure Boot result aggregation and module evidence reporting.
   Require an explicit expected release; distinguish FAIL, UNKNOWN and N/A.
2. Test and fix diagnostic private output and s2idle validation, without
   exercising the live suspend path.
3. Test and fix image signing with private staging, expected input hash,
   certificate verification before replacement and rejection of unsupported
   modular signing (including compressed modules). No new signing-key model.
4. Test and implement a focused provenance helper. Require an explicit archive
   digest, detached signature, trusted keyring and expected fingerprint. Compare
   source bytes to authenticated extraction before executing make. Reject stale
   or changed trees. Build only in a new private workspace, never delete old
   trees. Local patches remain unsupported and fail closed until reviewed.
5. Add a JSON provenance manifest with explicit unknown signed-image state;
   wire source/version/release/config/firmware identity into the build helper.
6. Add a current-candidate descriptor, static CI checks and negative fixtures.
   Preserve historical failed configs. Run applicable static checks and document
   platform limits, before/after properties, and remaining unknowns.

Each concern gets failing behavioral tests before implementation and a focused
commit after verification. Existing Bash/GNU tools, GPG, OpenSSL and sbsigntools
are reused; no new runtime dependency is introduced. Linux-only crypto and
filesystem semantics are tested in CI, with explicit local skips if unavailable.
No push is part of this assignment.
