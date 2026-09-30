# Audit11 owner install and supervised validation

Status, 30 September 2026: audit11 is **built and MOK-signed, but not
installed or booted**. The build used the committed audit10 effective config
plus exactly three `y`-to-`n` cuts and a unique `LOCALVERSION`. It preserves
Intel KVM, core io_uring, ThinkPad ACPI, Snap/SquashFS, storage, networking,
graphics, audio, and the audit10 crash-diagnostic policy. Audit10 remains the
running kernel; older custom and stock Ubuntu kernels remain installed.

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
checks proves a successful boot or complete hardware operation.

The automated agent could not perform installation because `sudo -n -l`
reported interactive authentication required. When physically present with
recovery credentials, run the following **single block** in your own terminal.
It verifies the package digest before writing, installs the exact-release
dracut firmware drop-in before the package, updates GRUB, and checks the
installed image/config. It does **not** reboot or change GRUB's default.

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
dpkg-query -W "linux-image-$release" linux-image-6.18.53-lockdown-t14g3-audit10 linux-image-7.0.0-34-generic
AUDIT11_INSTALL
```

Stop and share the full output if any command fails. Do not repeat `dpkg -i`
blindly after a partial failure. After a clean install, inspect the generated
initramfs and boot menu **before** a supervised boot:

```bash
sudo -v && sudo -n bash -euo pipefail <<'AUDIT11_PREBOOT'
release=6.18.53-lockdown-t14g3-audit11
lsinitrd "/boot/initrd.img-$release" | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
lsinitrd -f etc/cmdline.d/20-crypt.conf "/boot/initrd.img-$release"
lsinitrd -f etc/crypttab "/boot/initrd.img-$release"
grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit(10|11)|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIME)=' /etc/default/grub
AUDIT11_PREBOOT
```

The crypt cmdline and crypttab must name LUKS UUID
`6dc6712f-ec48-4782-a37a-9cef06b82a0d`; the root LV remains
`ubuntu-vg/ubuntu-lv`. Check both `regulatory.db` and `.p7s`, required early
i915/MT7961/SOF firmware, Intel microcode, crypt/LVM/rootfs support, audit10,
and stock fallback entries. A matching config, signature, and initramfs are
preboot evidence only. Keep `GRUB_DEFAULT=0` and manually select audit11 from
the visible Advanced options menu for one supervised boot. Do not queue
`grub-reboot` or remove any fallback. After boot, record `uname -r`, root
mount, Secure Boot/lockdown, failed units, Wi-Fi, display/input/audio,
USB-C/HDMI/storage, suspend/resume, KVM guest, and fallback results. Anything
not tested remains open; do not infer a power or security-gain magnitude from
three disabled options.
