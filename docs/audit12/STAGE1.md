# Audit12 stage 1: remove kernel sample code

Status, 30 September 2026: **built; unsigned and not installed**. Audit11 remains the running kernel. Audit12 starts from the committed
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
The audit12 build completed from the authenticated pristine Linux 6.18.53
archive using GCC 15.2.0 and GNU ld 2.46. Its provenance manifest records the
requested config SHA-256 `30ec26b9a2be1aceffe9c09319c8e0f394d6fb453d6835ea2f7a3cba3a9c7e30`,
resolved config SHA-256 above, and firmware drop-in SHA-256
`327dc28f18f5fbcbb527214ab2bb88fbc1826e2db77375206a0df6384e192642`.
The retained build workspace is `build/audited.pYoSv3pP/`; the owner-facing
copy is `build/audit12-final/unsigned/`. The kernel image package is
`build/audit12-final/unsigned/linux-image-6.18.53-lockdown-t14g3-audit12_6.18.53-1_amd64.deb`,
39,579,748 bytes, SHA-256
`1e2a176d1cc070eaaade6a67ccaec80bf37822644ac46494596177ebe9485ce6`.
The accompanying `linux-libc-dev` package is not needed to install this kernel;
its SHA-256 is `f27c044cdb8839c3017e91cdeb9363f78bc10081ec184b18314999077ec8266c`.
The build wrapper passed its exact package/config/image identity check and wrote
`build/audit12-final/unsigned/manifest.json`. The matching resolved config is
`build/audit12-final/unsigned/resolved.config`. It did not sign or install
anything.

The candidate has **not** been MOK-signed, installed, inspected in its
generated initramfs/GRUB state, booted, or functionally tested. Audit11 and
stock Ubuntu recovery entries remain untouched. A successful compile is not a
boot or hardware/KVM validation result.

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
