# Lock_Down status and issue ledger

Status checked against the audit10 owner runbook and built audit11 candidate on
30 September 2026. A static check cannot close a boot or hardware issue.

## Current open issues and validation blockers

| Severity | Item | Current evidence and next step |
| --- | --- | --- |
| High | Audit10 physical function | The supervised audit10 boot established 12 CPUs, mapper root, Secure Boot with integrity lockdown, connected MT7921U Wi-Fi, and zero failed system units. The owner still needs internal/external display, brightness, audio, keyboard, TrackPoint, touchpad, direct USB-C DisplayPort, and post-resume function tests. See `docs/AUDIT10_OWNER_RUNBOOK.md`. |
| High | Complete KVM guest workflow | The diskless smoke passed twice. On audit10, a transient Ubuntu 24.04.5 guest booted under KVM to a serial login prompt from an isolated qcow2 overlay and shut down cleanly. The first launch obtained a DHCP lease; the second showed no lease, and the guest agent did not connect. Guest login, sustained networking, agent, and application workload remain unverified. See `docs/AUDIT10_OWNER_RUNBOOK.md`. |
| High | USB storage persistence | A 64 MiB read/copy/eject check was reported, but the first insertion logged a lost write on an improperly unmounted FAT volume. Reinsert and read back before claiming persistence; test additional storage paths as needed. |
| High | s2idle and recovery | Suspend/resume, post-resume peripherals, previous custom fallback, and stock rescue boot remain untested on audit10. Keep the owner-supervised recovery path. |
| Medium | USB-C/Thunderbolt policy | Historical audit3 NHI and `boltctl` observations do not prove firmware tunneling policy or direct USB-C DisplayPort function. Read ThinkLMI policy with owner privileges and perform physical port tests. |
| Medium | Power benefit | No matched stock-versus-candidate power comparison exists. Measure only after function and recovery validation. |
| High | Audit11 installation and runtime | The three-symbol proposal was resolved against authenticated Linux 6.18.53 source with zero collateral config changes. A unique audit11 package was built, MOK-signed, and statically checked, but sudo authentication was unavailable to the agent, so installation, generated initramfs, GRUB state, boot, physical hardware, KVM guest, suspend, and fallback remain unverified. Follow `docs/AUDIT11_OWNER_RUNBOOK.md`. |

## Resolved tooling and historical findings

Source provenance and freshness enforcement are implemented in
`scripts/verify-kernel-source.sh` and `scripts/build-kernel.sh`; their limits
are recorded in `docs/TOOLING_INTEGRITY.md`. The older open item below reflects
the audit3-era general build script and is retained for provenance, not current
status. The audit2 emergency boot and audit3 firmware/config findings likewise
remain historical. Audit10 runtime evidence supersedes their open-state wording
where it directly covers the same behavior. The tables below preserve the
original issue text and dates; see `docs/AUDIT3_BOOT_CHECKLIST.md` for that
supervised record.

### Historical audit2/audit3 issue ledger (as originally recorded)

| Opened | Severity | Issue | Status / next evidence |
| --- | --- | --- | --- |
| 2026-09-23 | Blocker | Failed audit2 boot: emergency mode, two-CPU limit, missing loop/CP437, no integrity lockdown | Static remediation in audit3 config; close only after audit3 boots and the hardware checklist passes. Do not select the failed audit2 entry. |
| 2026-09-23 | High | i915 DMC/GuC firmware load failed and GPU wedged on audit2 | Audit3 rebuilt initramfs now contains required i915 firmware. Candidate journal and physical display/backlight/monitor tests remain pending. |
| 2026-09-23 | High | External MT7921U firmware initialization timed out on audit2 | Audit3 rebuilt initramfs now contains both MT7961 firmware files. Live association/network test remains pending. |
| 2026-09-24 | High | Audit3 enables unrelated flash and wireless test drivers | First boot raises an `ioremap on RAM` warning from `CONFIG_MTD_NETtel=y`; `CONFIG_IEEE802154_HWSIM=y`/`FAKELB=y` create fake wpan interfaces and recurring errors. Audit5's resolved config removes the 802.15.4 stack and passes static gates; its build, signing, installation and runtime validation are separate. NETtel remains enabled outside this requested delta. |
| 2026-09-23 | Medium | USB-C UCSI error and Thunderbolt firmware policy remain unresolved | Audit3 `boltctl` has no domains/devices; NHI PCI functions enumerate with no driver bound. Read root-only ThinkLMI `ThunderboltAccess`, inspect UEFI for separate PCIe-tunneling control, and test actual USB-C DisplayPort/role/charging. Enumeration is not evidence of an authorized tunnel. |
| 2026-09-23 | Medium | Historical `grub-editenv` hostdisk error; one-shot boot untested | Latest local-sudo read-back has no hostdisk error and reports empty `next_entry`; no one-shot is queued. Generated default 0 selects stock 7.0.0-34; known-good 7.0.0-31 and audit3 entries exist. Prefer supervised manual selection and confirm fallback boot. |
| 2026-09-24 | Medium | The general build script still gives manual source-verification instructions and can reuse an extracted tree | Audit3 used a separately verified tarball and fresh extraction. Automate provenance/freshness enforcement before relying on the general script for another release. |
| 2026-09-21 | Medium | Candidate power/battery benefit is unmeasured | Matched stock-vs-candidate runtime measurements after functional validation. |

## Closed or corrected premises

| Date | Item | Evidence |
| --- | --- | --- |
| 2026-09-24 | Audit3 initramfs firmware omission | Exact-release dracut drop-in installed; rebuilt image SHA-256 `de381c6969713e94ea2200cafbe9a869ae217076f4f87478e3bebc50de55ff7d` lists all requested i915/MT7961/SOF files, SOF target and HDA topologies. Root settings and microcode remain present. Static omission closed; hardware behavior is not yet validated. |
| 2026-09-24 | First audit3 boot reached userspace | Boot ID `7c6b86be-90b4-42cf-9fb1-a7c33d0674b6`; Secure Boot/integrity lockdown, 12 CPUs, LUKS/LVM ext4 root, TPM, microcode 0x43b, DMAR/IRQ remapping, CP437 EFI mount, i915 firmware and MT7921U association confirmed. Zero failed systemd units, Snap loop/SquashFS mounts present, one-packet gateway test passes. Physical display/audio/input/suspend, broader network, NVMe health and stock fallback plus unrelated-driver cleanup remain open. |
| 2026-09-24 | Upstream 6.18.53 source signature | GPG GOODSIG/VALIDSIG with Greg Kroah-Hartman's kernel.org-published fingerprint; source tar SHA-256 is recorded in the audit PDF. |
| 2026-09-25 | Claim that `/swap.img` is unencrypted | Rejected: `swapon --show` shows the active 8 GiB file; `findmnt -T /swap.img` resolves to `/dev/mapper/ubuntu--vg-ubuntu--lv`, and `lsblk -s` traces that LV through `dm_crypt-0` to a `crypto_LUKS` partition. Swap remains unchanged. |
