# Audit12 stage-0 hardening review

**Status: REVIEW_REQUIRED — no cut recommended yet.** Reviewed 30 September
2026 on `research/audit12-stage0` from `origin/main` commit
`97c83f2e5e4b17411d3722d09ca851087633f5c0`. This is a Windows-based
document review. It is not an audit12 candidate, a Linux host inventory, or a
fresh Kconfig resolution.

## Baseline and evidence ledger

The authoritative input is
[`candidate-6.18.53-lockdown-t14g3-audit11.config`](../../config/candidate-6.18.53-lockdown-t14g3-audit11.config),
SHA-256 `0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`.
It matches the digest in the [audit11 owner runbook](../AUDIT11_OWNER_RUNBOOK.md).
[`current-candidate.txt`](../../config/current-candidate.txt) still selects
audit11. The inspected source definitions below are from Greg Kroah-Hartman's
`v6.18.53` stable-tree mirror; they are useful source-text evidence, but this
Windows review did not authenticate a release archive or run Kbuild.

| Label | Finding and evidence |
| --- | --- |
| FACT — tracked config | `USBIP_CORE`, `USBIP_VHCI_HCD`, and `USBIP_HOST` are `y`; VHCI has 8 ports and 1 controller. `WATCHDOG`/`WATCHDOG_CORE` and many watchdog leaves are `y`. `FUSE_FS`, `VIRTIO_FS`, `FUSE_DAX`, `FUSE_PASSTHROUGH`, and `FUSE_IO_URING` are `y`. These are values in the committed resolved audit11 snapshot, not a new resolution. |
| FACT — recorded Linux checkpoint | Audit11 booted with Secure Boot and integrity lockdown, mapper-backed ext4 root, and zero failed units. Two diskless KVM boots passed; a real Ubuntu guest reached serial login and shut down. The second launch had no DHCP lease and no responding guest agent. See the [runbook](../AUDIT11_OWNER_RUNBOOK.md) and [open issues](../../ISSUES.md). |
| FACT — historical USB evidence | The audit9 Linux inventory recorded virtual USB/IP VHCI hubs and the MT7921U adapter; audit10 explicitly left USB/IP unchanged. See the [audit log](../kernel-audit-change-log.ms) under “AUDIT10 USB SPECIALTY-DRIVER REDUCTION.” This establishes a loaded virtual host path at that checkpoint, not a required remote workflow on audit11. |
| INFERENCE | Removing USB/IP would remove the kernel import/export implementation and the virtual host controller. It could narrow a privileged, configured USB/IP path. The security effect depends on actual service and device exposure; no vulnerability or power saving is established. |
| UNKNOWN | Audit11 USB/IP service state, attachments, users, remote tokens/recovery, guest/development dependencies, current watchdog bindings and ACPI WDAT presence, FUSE subfeature consumers, and exact resolved collateral changes after a proposal. No Linux 6.18.53 source archive, detached signature, trusted keyring, and pinned signer were available for an authenticated analysis in this Windows checkout. |

## Candidate comparison

| Track | Source and current value | Why it could matter | Blocking evidence / decision |
| --- | --- | --- | --- |
| USB/IP, one conditional set | Three `=y` symbols in `drivers/usb/usbip/Kconfig`; source [Kconfig](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/usbip/Kconfig) and [Makefile](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/usbip/Makefile). | The built-in core, virtual host, and export driver provide remote USB paths when configured by userspace. | Virtual hubs were observed historically. Import/export, token, rescue and VM needs are UNKNOWN. This is the only bounded set worth asking the owner about first. |
| Non-platform watchdog leaves | `WATCHDOG_CORE=y`; `LENOVO_SE10_WDT`, `LENOVO_SE30_WDT`, `CROS_EC_WATCHDOG`, `WDAT_WDT`, `ITCO_WDT`, and `INTEL_MEI_WDT` are `y`. Source [Kconfig](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/watchdog/Kconfig). | Some leaves have narrow DMI or device bindings; others can serve firmware, ACPI, or Intel recovery. | The source's SE10 DMI products include `12NH`–`12NM`, `13LJ`–`13LK`, and `13S1`–`13S6`; SE30 includes `11NA`–`11NC` and `11NH`–`11NK`. The supported ThinkPad is type `21AJ`, so these two Lenovo appliance drivers appear mismatched. The full set of watchdog devices, ACPI WDAT table, active `/dev/watchdog*` ownership, and suspend/crash behavior remain UNKNOWN. Defer every toggle. |
| Optional FUSE subfeatures | `FUSE_FS=y`, `VIRTIO_FS=y`, `FUSE_DAX=y`, `FUSE_PASSTHROUGH=y`, `FUSE_IO_URING=y`; source [Kconfig](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/fs/fuse/Kconfig). | `FUSE_DAX` enables virtiofs direct access, passthrough bypasses a FUSE server for selected operations, and `FUSE_IO_URING` enables that request transport. | Core FUSE/AutoFS stays. The [untrusted VM profile](../VM_THREAT_MODELS.md) forbids virtiofs sharing, but that policy does not inventory every guest, desktop mount, container, or recovery consumer. Defer optional leaves and keep this track separate from USB/IP. |

The watchdog source has more distinctions than the `=y` list alone shows:
`CROS_EC_WATCHDOG` depends on `CROS_EC`; `WDAT_WDT` depends on ACPI and
selects `ACPI_WATCHDOG`; `ITCO_WDT` depends on x86/PCI, I/O port and optional
I2C/MFD conditions; `INTEL_MEI_WDT` depends on `INTEL_MEI && X86`.
The [SE10](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/watchdog/lenovo_se10_wdt.c)
and [SE30](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/watchdog/lenovo_se30_wdt.c)
drivers check explicit DMI product names. WDAT reads the ACPI `WDAT` table and
has [suspend/resume paths](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/watchdog/wdat_wdt.c).
No Windows observation can establish whether any of these drivers currently
bind on the ThinkPad. Keep the watchdog core and Intel/ACPI paths while the
owner checks Linux runtime evidence and recovery requirements.

The FUSE Kconfig makes `FUSE_DAX` depend on `VIRTIO_FS`, `FS_DAX`, and `DAX`;
`FUSE_PASSTHROUGH` depends on core FUSE and selects `FS_STACK`;
`FUSE_IO_URING` depends on core FUSE and `IO_URING`. `FUSE_FS` selects
`FS_POSIX_ACL` and `FS_IOMAP`. These direct clauses do not establish all
reverse selectors or active consumers. The upstream [Kconfig language guide](https://docs.kernel.org/6.18/kbuild/kconfig-language.html)
explains why menu inheritance, `select`, and `imply` prevent treating a text
edit as a resolved result.

## USB/IP set for owner decision only

| Symbol | Current → possible request | Definition and relationships | Runtime path and regression |
| --- | --- | --- | --- |
| `CONFIG_USBIP_CORE` | `y → n` | Tristate, `depends on NET`, `select USB_COMMON` and `SGL_ALLOC`; in the `USB_SUPPORT` menu (`depends on HAS_IOMEM`). VHCI, HOST, and VUDC directly depend on it. No direct `imply` or selector of CORE was found in the inspected USB/IP file; whole-tree reverse dependencies are UNKNOWN. | Shared USB/IP transport disappears. Remote USB import and export stop; any recovery or token workflow using them would fail. |
| `CONFIG_USBIP_VHCI_HCD` | `y → n` | Tristate, `depends on USBIP_CORE && USB`. Its port/count settings depend on it; source currently records 8 ports and 1 controller. No direct `select`/`imply` in its definition. | Virtual host controller and remote-device import disappear. A previously attached remote device or guest/development process may no longer work. |
| `CONFIG_USBIP_HOST` | `y → n` | Tristate, `depends on USBIP_CORE && USB`; no direct `select`/`imply` in its definition. | Export/stub driver disappears. A remote client cannot use local devices through this kernel path. |

Source: [USB/IP Kconfig](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/usbip/Kconfig),
[USB parent menu](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/Kconfig),
and [USB/IP objects](https://raw.githubusercontent.com/gregkh/linux/v6.18.53/drivers/usb/usbip/Makefile).
`USBIP_VUDC` additionally depends on `USB_GADGET`, which is disabled in the
baseline. Its final emitted state and the VHCI integer settings after a cut
must be learned from authenticated Kconfig resolution; likely collateral
effects are not silently counted as approved changes.

The local NVMe/LUKS boot path has no USB/IP dependency in the inspected
definitions. That is a bounded inference about direct Kconfig relationships,
not evidence that the owner never uses remote USB for login, recovery, or VM
operations. The audit11 guest test used virtio networking and a read-only
seed ISO, with no documented USB/IP attachment; other workflows remain UNKNOWN.
Physical USB xHCI, HID, mass storage/UAS, MT7921U Wi-Fi, direct USB-C display,
and HDMI must remain supported. No power benefit is claimed.

### Required validation if the owner approves this set

1. On the Linux host, record USB/IP service configuration, virtual hub and
   attachment state, exportable/bound devices, and whether remote tokens,
   development tools, recovery, or any guest needs import/export. Preserve
   identifiers privately; a quiet moment is not proof of non-use.
2. Resolve only the approved three assignments against an authenticated exact
   Linux 6.18.53 archive with the [Kconfig analyzer](../../scripts/analyze-kconfig-delta.py).
   Review every requested, rejected, and collateral symbol, including VHCI
   port/count values; require the existing boot/security gates to pass. An
   unexpected delta ends this proposal for renewed review.
3. Before any owner-authorized build or install, retain the signed audit11 and
   stock Ubuntu recovery entries. On a supervised boot of a separate candidate,
   verify Secure Boot/integrity lockdown, encrypted root, CPUs, failed units,
   USB input/storage/Wi-Fi, display, audio, real KVM guest, and the specific
   workflows the owner confirmed. Test s2idle and post-resume function, then
   boot the previous custom and distro fallbacks. Record outcomes separately.

Rollback is an owner-supervised selection of the retained signed audit11 or
stock kernel from the visible boot menu, followed by restoration of the
previous candidate as the default only after the failure is understood. No
GRUB or fallback setting is changed by this review.

## Recommendation and owner gate

**Recommend no audit12 config cut at this checkpoint.** USB/IP is the sole
conditional first set because its three drivers form a reviewable function
boundary. The recorded virtual hubs make a non-use claim unjustified. Watchdog
and FUSE changes require separate runtime/device and consumer evidence and
must not be bundled with USB/IP.

Owner decision needed: **Do you require USB/IP import or export for remote USB
devices, tokens, recovery, development, or any guest workflow?** If all are
ruled out, the next authorized step is an exact-source resolved analysis of
the three requested `y → n` assignments. A later build/deployment decision
remains separate. Until that answer, keep the current audit11 values.

Audit11 itself still needs physical display/input/audio/USB and USB-C/HDMI,
guest login plus sustained networking/agent/workload, s2idle with post-resume
checks, crash diagnostics, and actual fallback/default boots before any
promotion claim. The first audit11 guest's serial login and clean shutdown do
not close those items. See [runbook](../AUDIT11_OWNER_RUNBOOK.md) and
[issues](../../ISSUES.md).
