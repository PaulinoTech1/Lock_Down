# Audit11 owner install and supervised validation

Status, 30 September 2026: audit11 is **built, MOK-signed, installed, and
running**. Its basic boot checks passed; the owner has **not yet tested physical
hardware, a KVM guest, suspend/resume, or fallback**. The build used the
committed audit10 effective config plus exactly three `y`-to-`n` cuts and a
unique `LOCALVERSION`. It preserves
Intel KVM, core io_uring, ThinkPad ACPI, Snap/SquashFS, storage, networking,
graphics, audio, and the audit10 crash-diagnostic policy. Audit10 and stock
Ubuntu remain installed as recovery choices.

Release: `6.18.53-lockdown-t14g3-audit11`. Debian package version:
`6.18.53-1`. The image package is:

```text
/home/the-ascended1/Lock_Down/build/audit11-final/signed/linux-image-6.18.53-lockdown-t14g3-audit11_6.18.53-1_amd64.deb
```

SHA-256:
`2f19c8a63fef4cf755fa6c2d6b30148e8a053f304f7314a61a8e4a1578209b8a`.
The EFI image *inside* the package is signed with the existing MOK; the outer
`.deb` is not signed. The signed inner image SHA-256 is
`c78f8b73538b9e0c5f488f82e93b4794e2a06934c667e624f326f5d27de7f3c6`.
The embedded config SHA-256 is
`0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`.
The build manifest and log are retained under `build/audit11-final/` (ignored
by Git). The source archive digest and detached signature passed the pinned
source-verifier checks; the build wrapper passed exact package/config/image
identity. A fresh extraction of the repacked package passed all eight payload
MD5 checks, exact config comparison, MOK-certificate signature verification,
and the no-loadable-modules check. Static policy gates passed. None of those
checks alone proves a successful boot or complete hardware operation. The
separate runtime checkpoint is recorded below.

## Historical installation and preboot commands (completed; do not rerun)

The automated agent could not authenticate sudo; the owner ran this block in
their own terminal. It verified the package digest before writing, installed
the exact-release dracut firmware drop-in before the package, updated GRUB,
and checked the installed image/config. The package installed as version
`6.18.53-1`, generated a 26 MiB initramfs, and `sbverify` reported signature
verification OK. `dpkg`/dracut emitted missing-firmware and `/proc/modules`
warnings from built-in drivers; these did not stop installation. The block did
not reboot or change GRUB's default.

```bash
sudo -v && sudo -n bash -euo pipefail <<'AUDIT11_INSTALL'
release=6.18.53-lockdown-t14g3-audit11
package=/home/the-ascended1/Lock_Down/build/audit11-final/signed/linux-image-6.18.53-lockdown-t14g3-audit11_6.18.53-1_amd64.deb
expected=2f19c8a63fef4cf755fa6c2d6b30148e8a053f304f7314a61a8e4a1578209b8a
actual=$(sha256sum -- "$package" | cut -d' ' -f1)
test "$actual" = "$expected"
install -m 0644 /home/the-ascended1/Lock_Down/config/60-lockdown-audit11-firmware.conf /etc/dracut.conf.d/60-lockdown-audit11-firmware.conf
dpkg -i "$package"
update-grub
sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem "/boot/vmlinuz-$release"
cmp -- /home/the-ascended1/Lock_Down/config/candidate-6.18.53-lockdown-t14g3-audit11.config "/boot/config-$release"
test -s "/boot/initrd.img-$release"
AUDIT11_INSTALL
```

The owner then ran the following preboot inspection. It showed the LUKS UUID
and root LV below, Intel microcode, crypt/LVM/rootfs tools, i915 ADL/TGL,
MT7961 and SOF firmware, plus `regulatory.db` and its `.p7s` signature. GRUB
listed audit11 and audit10 in Advanced options, with stock 7.0.0-34-generic
as the first normal entry. The displayed output is preboot evidence, not a
hardware test.

```bash
sudo -v && sudo -n bash -euo pipefail <<'AUDIT11_PREBOOT'
release=6.18.53-lockdown-t14g3-audit11
lsinitrd "/boot/initrd.img-$release" | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
lsinitrd -f etc/cmdline.d/20-crypt.conf "/boot/initrd.img-$release"
lsinitrd -f etc/crypttab "/boot/initrd.img-$release"
grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit(10|11)|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
AUDIT11_PREBOOT
```

The crypt cmdline and crypttab named LUKS UUID
`6dc6712f-ec48-4782-a37a-9cef06b82a0d`; the root LV remains
`ubuntu-vg/ubuntu-lv`. `GRUB_DEFAULT=0`, visible menu style, and 15-second
timeout remained configured. The recorded install/preboot commands did not
invoke `grub-reboot` or remove a fallback kernel.

## First supervised boot: basic checkpoint only

The owner reported selecting audit11. Live read-only checks on 30 September
2026 confirmed boot ID `b0650e43-b758-43ad-98ff-6eb57019946c` and the
following state:

```text
$ uname -r
6.18.53-lockdown-t14g3-audit11
$ findmnt -no SOURCE,FSTYPE /
/dev/mapper/ubuntu--vg-ubuntu--lv ext4
$ cat /sys/kernel/security/lockdown
none [integrity] confidentiality
$ mokutil --sb-state
SecureBoot enabled
$ systemctl --failed
0 loaded units listed.
```

The installed config matched the reviewed audit11 snapshot at SHA-256
`0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`,
and `/boot/vmlinuz-6.18.53-lockdown-t14g3-audit11` passed `sbverify` against
the existing MOK certificate. This establishes a successful basic boot and
root unlock, **not** the hardware checklist. The owner explicitly said no
hardware tests have been done yet. Wi-Fi use, display/input/audio, USB-C,
HDMI, USB storage, KVM guest, suspend/resume, crash diagnostics, and an actual
fallback/default reboot remain untested on audit11. Keep the stock and audit10
fallbacks; do not infer a power or exploit-mitigation magnitude from three
disabled options.
