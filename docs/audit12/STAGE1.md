# Audit12 stage 1: remove kernel sample code

Status, 30 September 2026: **built, MOK-signed, installed, and basic-boot verified**. The current running kernel is audit12. Audit12 starts from the committed
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
`build/audit12-final/unsigned/resolved.config`. The signed image package is
`build/audit12-final/signed/linux-image-6.18.53-lockdown-t14g3-audit12_6.18.53-1_amd64.deb`,
SHA-256 `3485262e37281c3b0b102fa62a86b2a95fbc694ada2f563225b0f59500544e35`.
Its embedded kernel image SHA-256 is
`ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d` and
passed `sbverify` against the enrolled MOK certificate. All package payload
MD5 checks passed and the embedded config still matches the resolved snapshot.
The outer `.deb` container itself is not cryptographically signed.

Installation and static preboot checks completed. The first supervised boot
reached the mapper-backed ext4 root with Secure Boot enabled and integrity
lockdown active; `systemctl --failed` listed no failed units. The recorded boot
ID is `185290d8-83a0-4134-a3af-2173a3ffc147`. Audit11 and stock Ubuntu
7.0.0-34 remain installed. The first-boot kernel log includes probe failures
from unrelated legacy framebuffer/platform drivers and watchdog registration
conflicts; see the owner runbook. These did not prevent this boot, but are
recorded as cleanup/diagnostic findings, not silently dismissed.

At the initial hardware checkpoint, the owner reported audit12 passes for speakers, USB storage, USB Wi-Fi,
microphone, HDMI, USB-C, touchpad, and TrackPoint/nub; headphone jack is out of
scope. Keyboard, brightness/hotkeys, USB persistence after reconnect, real-
guest login/network/agent/workload, suspend/resume, crash-dump, and fallback
validation were still open at that checkpoint. The diskless deterministic KVM smoke passed
2/2 using this running kernel image (SHA-256
`ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d`); the
fixture initramfs SHA-256 is
`bc75010a0af460d9a6b831d78fe6f9da7bf037dd641db813b0743926fe14f7b5`. This
does not establish real-guest login/network/agent/workload. Do not infer
complete function from a basic boot and smoke test. See
[`docs/AUDIT12_OWNER_RUNBOOK.md`](../AUDIT12_OWNER_RUNBOOK.md) for the
signed-package, install, preboot, and basic-boot evidence.

The owner subsequently confirmed `systemctl --failed --no-pager` listed zero
failed units and inspected GRUB: `GRUB_DEFAULT=0`, menu style, timeout 15,
audit12/audit11/Ubuntu 7.0.0-34 entries present, and empty `next_entry`. A
manual `virsh console lockdown-audit12-vmtest` attempt returned
`failed to get domain`; the VM had not yet been created or started, so this is
not a guest boot failure and no real-guest result is established. The corrected
`sudo -v && sudo -n` start command and then-console sequence are recorded in
the owner runbook. A later multiline paste yielded no output; read-only checks
found no audit12 VM process, domain, or overlay, consistent with an unfinished
heredoc. `scripts/audit12-vm-start.sh` now provides phase output and avoids the
multiline terminal paste.

The first scripted audit12 guest launch was observed from 21:48:45 to 21:49:01
on 30 September. The libvirt DHCP server assigned `192.168.122.182`; the
transient domain then disappeared while its separate audit12 overlay remained.
This proves guest creation and a brief network bring-up, not login, agent,
workload, or sustained networking. The runbook gives an `--existing-overlay`
retry command that checks the overlay before a second launch.

The second launch remained running and reached a serial login prompt, but the
original seed contains no guest user, password, or SSH key and sets
`ssh_pwauth: false`. The owner had no guest credentials. The guest agent did
not respond and the only DHCP lease was from the first launch. The transient
guest was requested to shut down and disappeared from libvirt's domain list.
`scripts/audit12-vm-login-test.sh` created a separate disposable overlay and
NoCloud seed with a locally entered password hash. The owner reports a
successful serial-console login as `audit12`. Host checks show the guest
running with 2 vCPUs, 2 GiB RAM, and a DHCP lease of `192.168.122.59/24`.
The owner then reported the guest NIC up with the same IPv4 address, a default
route through `192.168.122.1`, three successful gateway pings, DNS resolution
for `ubuntu.com`, and a 64 MiB zero-file write/hash matching an independent
host calculation. The guest agent was inactive and did not respond from the
host at that checkpoint. The owner then installed `qemu-guest-agent` in the
disposable guest, started its static service, and reported it active. Host-side
`guest-ping` returned `{"return":{}}`. The package download exercised
outbound access to Ubuntu repositories. A libvirt graceful shutdown request
completed, and the transient domain disappeared; the host audit12 kernel
remained active with zero failed units. The planned real-guest VM workflow
passed on this disposable test fixture.

The owner then completed one short supervised s2idle cycle. The kernel logged
suspend entry at 22:40:51 and exit at 22:41:00. The immediate post-resume
snapshot showed the MT7921U Wi-Fi interface without carrier, but it
re-associated and obtained `192.168.1.15` by 22:41:03; a later check showed
the `Paulino` connection active. The owner confirmed three successful gateway
pings to `192.168.1.1` (0% loss) and DNS resolution of `ubuntu.com` to
`185.125.190.29`, so functional Wi-Fi recovery passed. There were no
error-priority kernel messages in that window and no failed host units.
Display, input, and audio function after
waking still need owner confirmation. This cycle does not measure suspend
battery drain.

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
