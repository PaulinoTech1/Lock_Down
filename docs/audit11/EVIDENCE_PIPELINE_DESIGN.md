# Audit11 decision and validation evidence design

Status: tooling design, not an audit11 kernel configuration or a promotion.
The audit10 effective config and historical owner evidence stay unchanged.

## Boundaries

1. `scripts/analyze-kconfig-delta.py` analyzes a small human-authored proposal.
   It authenticates an exact upstream archive with the existing source verifier,
   resolves two copies of the baseline using Kbuild `O=`, and writes a report.
   It never emits a candidate config for installation or chooses a symbol value.
2. `scripts/collect-validation-evidence.py` gathers bounded, read-only host
   observations. It can consume an offline fixture root on Windows. The live
   mode is Linux-only and invokes the existing Secure Boot verifier. It never
   runs a physical test, changes host policy, or declares a kernel validated.
3. `validation.json` contains observations and statuses. `validation.md`
   contains an unchecked owner checklist. CI runs only offline fixtures.
4. Human review, authenticated build, signing, installation, physical tests,
   fallback tests, and promotion remain separate owner decisions.

## Kconfig analyzer contract

Inputs: exact `--version`, signed `linux-VERSION.tar.xz`, independently reviewed
SHA-256, detached signature, pinned signer fingerprint and trusted public
keyring; current effective `--baseline`; small `--proposal`; new `--output`.
The archive is the source-tree input. The existing verifier creates a fresh
authenticated tree in private scratch space. Neither an arbitrary existing
source tree nor an untrusted Git checkout is accepted. The source identity in
the report is the authenticated archive digest and signer, not a proof that a
subsequently copied tree stayed immutable.

Proposal lines are `CONFIG_NAME=value` or `# CONFIG_NAME is not set`.
Duplicate or malformed lines fail. Values are preserved literally so numeric
and quoted Kconfig values can be proposed, but no shell evaluation occurs.
One proposal and twenty proposals use the same path.

The baseline is copied twice. Kbuild resolves the first copy without edits;
any drift from the supplied effective baseline fails as `BASELINE_DRIFT`.
The second copy receives only proposed assignments, then Kbuild resolves it.
The analyzer compares the full symbol maps, including absent symbols. It
classifies requested symbols as accepted, unchanged, or rejected by Kconfig,
and all other effective changes as collateral. A rejected request or required
policy failure returns nonzero while retaining the report for review.

The report includes every changed symbol, the complete unified config diff,
required-symbol results, exact gate commands and exit codes, kernel version
and release, input hashes, source identity, and `review_required: true`.
Kconfig definitions are indexed as source text for affected symbols:
direct `depends on`, `select`, and `imply` clauses and reverse references.
Menu nesting, architecture visibility, hidden symbols, and conditional
expressions cannot be completely resolved by this bounded index. Those fields
are explicitly UNKNOWN unless directly supported. Effective values come from
Kbuild, never this index. Hardware relevance is always UNKNOWN absent a
reviewed repository mapping. The index is evidence for a human, not a second
Kconfig implementation.

The generic project gates are preflight-check, preflight-security,
validate-boot-critical, audit-config, and the retained audit8/9/10 invariant
tests. These are run against the proposed resolved config, with output bounded
in the report. Some historical gates may reject a future deliberate policy
change; their failure requires human review rather than automatic weakening.

The machine-readable output is `lockdown.kconfig-analysis.v1`, specified in
`docs/audit11/schemas/kconfig-report.schema.json`. Exit 0 means analysis and
required gates completed without rejection; it never means the proposal is
approved. Exit 1 means invalid evidence, rejected request, or policy failure;
2 means invalid invocation; 3 means a required tool or evidence is unavailable.

## Validation collector contract

The collector accepts `--expected-kernel`, a new private `--output`, and
optional `--evidence-root` for offline fixture data. Live collection requires
Linux. The output contains only `validation.json` and `validation.md`; no raw
journal, environment, command line, serial, MAC, IP, SSID, LUKS UUID, guest
name, or secret is stored. `/proc/cmdline` is reduced to an allowlist of
security-relevant parameter names and safe fixed values, with all other values
omitted. Kernel log collection is bounded and reported as category counts,
never raw lines. Missing or unreadable data remains UNKNOWN.

Checks cover release/config identity, Secure Boot and lockdown via the
existing verifier, CPU count/model/microcode, root mapper and NVMe type,
IOMMU/IRQ remapping, i915/DRM/firmware error counts, Wi-Fi USB identity and
binding, KVM prerequisites, USB VID:PID/driver topology, ALSA and input class
presence, selected/supported s2idle modes, failed unit count, and bounded
kernel error categories. Device enumeration can at most establish presence.
Physical display, input, audio, Wi-Fi traffic, USB storage, suspend/resume,
real VM boot, fallbacks, and power measurements stay MANUAL_TEST_REQUIRED.

All status values are PASS, FAIL, WARN, UNKNOWN, NOT_APPLICABLE, or
MANUAL_TEST_REQUIRED. The bundle manifest records repository commit, kernel
release, config and collector SHA-256, UTC time, evidence mode, and an optional
hostname hash. The hash is omitted by default. A manifest is not a signature
or trust certificate. Offline fixture results are labeled OFFLINE_FIXTURE and
cannot be promoted into live hardware claims.

The machine-readable output is `lockdown.validation.v1`, specified in
`docs/audit11/schemas/validation.schema.json`. Exit 0 means collection
completed, even if checks remain UNKNOWN or MANUAL_TEST_REQUIRED. Exit 1 means
an expected identity or required security check failed. Exit 2 is invocation
error; exit 3 is inability to collect required evidence. Output creation uses
a new private directory and exclusive files, never overwrites a prior bundle.

## Evidence quality and limitations

Synthetic fixtures verify classification and file safety. They do not prove
Linux 6.18.53 Kconfig behavior, a real authenticated release archive, a
successful build, or ThinkPad hardware behavior. The owner must run the
analyzer against the reviewed release archive and inspect collateral changes
before a build. The collector must later run on the actual ThinkPad; the owner
must complete the generated physical checklist and preserve the evidence.

References: [Linux 6.18 Kconfig language](https://docs.kernel.org/6.18/kbuild/kconfig-language.html)
and [Kbuild output directory](https://docs.kernel.org/6.18/kbuild/kbuild.html).
