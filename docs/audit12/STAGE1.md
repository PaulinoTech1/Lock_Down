# Audit12 stage 1: remove kernel sample code

Status, 30 September 2026: **candidate config resolved and gated; build not yet
run**. Audit11 remains the running kernel. Audit12 starts from the committed
audit11 effective configuration and requests one Kconfig change:

| Symbol | Audit11 | Requested/resolved | Effect |
| --- | --- | --- | --- |
| `CONFIG_SAMPLES` | `y` | `n` | Removes the kernel's sample-code subtree, including the enabled auxiliary-display, TSM measurement, and watchdog examples. Real watchdog support, Intel KVM, crash diagnostics, and laptop drivers remain enabled. |

The authenticated Linux 6.18.53 archive SHA-256 was
`4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0`; its
detached signature passed against pinned signer
`647F28654894E3BD457199BE38DBBDC86092693E`. The audit11 baseline hash is
`0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`. The
proposal report classified the request as accepted, with no rejected requests.
The complete Kconfig change set contains the unique `LOCALVERSION` change to
`-lockdown-t14g3-audit12`, the `CONFIG_SAMPLES=n` request, and the sample leaf
entries hidden by that parent. No non-sample effective values changed.

The proposed resolved config hash was
`c7e1400a99afeb420e9797cb47369faa07eb998d0e3dae3f8b60aa2efbc3a6cb` while
retaining audit11's release suffix. The separately resolved audit12 snapshot
hash is
`444f72d745665f63acce59b7dce4fa9793140acbe56fd643deeb4aedf6dbc911`.
The release snapshot differs from audit11 only in the release suffix and
sample-code settings. Kbuild reported release
`6.18.53-lockdown-t14g3-audit12`.

All seven config gates passed: preflight 83 pass/0 fail/0 warn, production
security policy 26 checks, boot-critical, project audit, and audit8, audit9,
and audit10 focused gates. `CONFIG_KVM=y`, `CONFIG_KVM_INTEL=y`,
`CONFIG_WATCHDOG=y`, `CONFIG_ITCO_WDT=y`, `CONFIG_KEXEC=y`,
`CONFIG_CRASH_DUMP=y`, `CONFIG_DRM_I915=y`, `CONFIG_USB_STORAGE=y`,
`CONFIG_THINKPAD_ACPI=y`, `CONFIG_DM_CRYPT=y`, and `CONFIG_SQUASHFS=y` remain.
These are static checks; no audit12 image has been built, signed, installed,
booted, or functionally tested yet.

Reproduce the authenticated delta analysis from the repository root with a
reviewed public keyring at `build/audit12-inputs/trusted.gpg`:

```bash
python3 scripts/analyze-kconfig-delta.py \
  --version 6.18.53 \
  --archive linux-6.18.53.tar.xz \
  --sha256 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0 \
  --signature build/audit3-final2/linux-6.18.53.tar.sign \
  --keyring build/audit12-inputs/trusted.gpg \
  --fingerprint 647F28654894E3BD457199BE38DBBDC86092693E \
  --baseline config/candidate-6.18.53-lockdown-t14g3-audit11.config \
  --proposal config/audit12-stage1-proposal.config \
  --output /tmp/audit12-analysis-reproduction
```

The build wrapper retains failed workspaces and creates a new private output
directory. It never installs or signs the package. Signing, install, initramfs
and GRUB review, supervised boot, hardware/KVM/suspend/fallback testing remain
separate checkpoints. Preserve audit11 and stock Ubuntu recovery entries.
