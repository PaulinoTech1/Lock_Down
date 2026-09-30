# Audit11 stage 1: three-symbol config review

Status on 30 September 2026: **static analysis complete; no audit11 candidate built**.
The proposal is [`config/audit11-stage1-proposal.config`](../../config/audit11-stage1-proposal.config).
Audit10's effective config remains the baseline and the currently booted kernel;
its candidate descriptor was not changed.

| Symbol | Audit10 | Proposed/resolved | Reason for review |
| --- | --- | --- | --- |
| `CONFIG_TEST_POWER` | `y` | `n` | Test power-supply device, not a required laptop power path. |
| `CONFIG_IO_URING_MOCK_FILE` | `y` | `n` | io_uring mock-file facility, not core io_uring support. |
| `CONFIG_THINKPAD_ACPI_DEBUGFACILITIES` | `y` | `n` | Optional ThinkPad ACPI debug interface; `THINKPAD_ACPI` stays `y`. |

Kbuild resolved the proposal against a fresh extraction of Linux 6.18.53.
The archive digest was
`4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0`;
the detached signature validated under the pinned signing fingerprint
`647F28654894E3BD457199BE38DBBDC86092693E` from the existing project
verification keyring. The audit10 baseline SHA-256 was
`121a6769868273d437d19d309a628793fabbec07f65e806568035740bd377f54`;
the proposal SHA-256 was
`9abbb8a85ec491cb8a94d12ee0cce9f96de44f58e50def12baeab76ac584937a`.
The proposed *resolved config* SHA-256 was
`643cb36498fb9fc7e665292cc7693cff6b54bbff70bb5ec55069b21bb2ce9672`.
All three requests were accepted; there were **zero collateral changes and zero
rejected requests**. The complete resolved diff consists only of these three
`y` to `n` assignments. All seven analyzer gates exited zero: preflight
(83 pass/0 fail/0 warn), security policy (26 checks), boot-critical, project
audit, and the audit8, audit9, and audit10 focused config gates.

The first two attempts did **not** reach Kconfig. The source verifier rejected
an authentic upstream filename with a space (`Dell Inc.,XPS 13 9300.yaml`),
then authentic `tools/` fixture headers named `autoconf.h`. Regression fixtures
were added before narrowing those two checks. Path traversal, absolute links,
generated `include/generated/`, object files, command files, and `vmlinux`
remain rejected. The source-provenance fixture suite now passes.

Reproduce the analysis from the repository root without root privileges:

```bash
stage_dir=$(mktemp -d /tmp/lockdown-audit11-stage1.XXXXXXXX)
gpg --homedir build/audit5-verify-gnupg --export \
  --output "$stage_dir/trusted.gpg" \
  647F28654894E3BD457199BE38DBBDC86092693E
python3 scripts/analyze-kconfig-delta.py \
  --version 6.18.53 \
  --archive linux-6.18.53.tar.xz \
  --sha256 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0 \
  --signature build/audit3-final2/linux-6.18.53.tar.sign \
  --keyring "$stage_dir/trusted.gpg" \
  --fingerprint 647F28654894E3BD457199BE38DBBDC86092693E \
  --baseline config/candidate-6.18.53-lockdown-t14g3-audit10.config \
  --proposal config/audit11-stage1-proposal.config \
  --output "$stage_dir/report"
```

Inspect `report.md` and `report.json` in the printed output directory. The
report includes the complete diff and gate outputs. Exit zero means analysis
completed, not that the proposal is promoted. A separate build/release decision
is required. The analysis deliberately retained audit10's `LOCALVERSION`, so
any later audit11 candidate needs a unique release identity and a new resolved
config and policy-gate run before a build. Signing, installation, boot, KVM,
physical, suspend, fallback, crash-dump, and power checks remain **not tested
for audit11**.
