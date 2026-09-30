# Audit11 evidence tooling

These tools produce review material. Neither creates an audit11 candidate or
performs a build, signing, installation, boot, suspend, or physical test.

## Tooling context and current release status

Audit11 is built, installed, and booted with basic root/Secure Boot checks,
but physical hardware, KVM guest, suspend/resume, and fallback tests remain
open. Audit10's earlier real KVM guest reached a serial login prompt and shut
down cleanly, but guest login, sustained network, guest agent, and workload
checks are still open. See the [audit11 owner runbook](../AUDIT11_OWNER_RUNBOOK.md)
and [issue ledger](../../ISSUES.md).

The audit11 release began with a small, reviewed proposal against the audit10
effective config. The analyzer ran against authenticated upstream source and
reported every accepted/rejected request, collateral delta, and policy gate.
An exit-zero analysis alone did not approve a build. The collector can now
record read-only host observations, but it cannot perform physical tests,
start a VM, or suspend the laptop.

The [stage-1 three-symbol review](STAGE1.md) records the first completed
proposal, its resolved diff, gate results, and reproducible command. It did
not create an audit11 candidate.

## Analyze a small config proposal on Linux

Create a proposal containing only intended assignments, for example:

```text
CONFIG_EXAMPLE=n
# CONFIG_OTHER is not set
```

Run from the repository root with an independently reviewed archive digest,
trusted kernel.org keyring, detached signature, and pinned signer fingerprint:

```bash
python3 scripts/analyze-kconfig-delta.py \
  --version 6.18.53 \
  --archive /path/to/linux-6.18.53.tar.xz \
  --sha256 REVIEWED_64_HEX_DIGEST \
  --signature /path/to/linux-6.18.53.tar.sign \
  --keyring /path/to/trusted-kernel-keyring.gpg \
  --fingerprint REVIEWED_40_HEX_FINGERPRINT \
  --baseline config/candidate-6.18.53-lockdown-t14g3-audit10.config \
  --proposal /path/to/proposal.config \
  --output /private/new-analysis-directory
```

The verifier extracts a fresh authenticated source in temporary storage.
Kbuild resolves both baseline and proposal in separate `O=` output trees.
The report preserves rejected requests and every collateral config delta.
Inspect `report.json` and `report.md`, including policy-gate failures and
UNKNOWN dependency context. Exit 0 means the analysis completed without a
detected policy failure; it does not approve the proposed change. Do not use
the resolved temporary config as a promoted candidate.

## Collect read-only host observations on the ThinkPad

After the owner separately builds, signs, installs, and boots an exact
candidate, run on that Linux host with a new private output directory:

```bash
python3 scripts/collect-validation-evidence.py \
  --expected-kernel 6.18.53-lockdown-t14g3-audit11 \
  --output /private/new-validation-directory
```

Root may be needed to read debugfs and all journal entries; missing data is
UNKNOWN rather than silently passed. The collector calls the existing Secure
Boot verifier, inventories safe hardware states, and writes `validation.json`
plus an unchecked `validation.md` physical checklist. It does not start a VM,
exercise devices, or suspend. Review the report before sharing it. Raw logs,
guest names, network identifiers, and the full kernel command line are not
stored. `--include-host-hash` adds a one-way hostname hash only if desired.

For offline development, `--evidence-root /path/to/fixture` consumes a
fixture tree with `commands/` snapshots and produces an explicitly labeled
`OFFLINE_FIXTURE` report. This mode does not inspect the Windows host or prove
ThinkPad behavior. The fixture tests show the expected layout in
`tests/test-validation-collector.py`.

Run static tests:

```bash
python3 -B tests/test-kconfig-analysis.py
python3 -B tests/test-validation-collector.py
```

Schemas: [Kconfig report](schemas/kconfig-report.schema.json) and
[validation report](schemas/validation.schema.json). The design explains
limitations in [EVIDENCE_PIPELINE_DESIGN.md](EVIDENCE_PIPELINE_DESIGN.md).
