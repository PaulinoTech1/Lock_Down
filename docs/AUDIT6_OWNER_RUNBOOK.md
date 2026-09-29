# Audit6 owner-run installation and supervised boot

Target: `6.18.53-lockdown-t14g3-audit6`. This hardware-reduction
checkpoint was installed and booted on 28 September 2026. Core runtime checks
passed; physical, VM-start, suspend, and fallback checks remain open.
The signed package's expected SHA-256 is
`f4d8ad715fa4c247a07807c88d580e0d3a04b5bd9584a7a6633ec7e0cfab9ffa`.
Do not install it if your local digest differs.
Keep stock Ubuntu `7.0.0-34-generic` and the previously booted audit3 kernel
installed. The older stock `7.0.0-31-generic` is now deinstalled (config
files only) and must not be assumed available as a fallback. Leave
`/swap.img` unchanged. No command here changes the GRUB default.

## Stage A — privileged installation and preboot inspection

These installation and preboot steps were completed on 28 September. Do not
repeat them unless intentionally reinstalling this exact package.

Run from `/home/the-ascended1/Lock_Down`, one command at a time. Stop and send
the full output if `dpkg`, signing verification, initramfs creation, or GRUB
generation reports an error. Do not reboot merely because `dpkg` exited zero.

```bash
cd /home/the-ascended1/Lock_Down
ls -l -- '/home/the-ascended1/Lock_Down/build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb'
sha256sum -- '/home/the-ascended1/Lock_Down/build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb'
sudo install -m 0644 config/60-lockdown-audit6-firmware.conf /etc/dracut.conf.d/60-lockdown-audit6-firmware.conf
sudo dpkg -i build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb
sudo update-grub
sudo sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem /boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
```

The `sha256sum` output must match the signed-package digest in the audit PDF
before running `sudo dpkg -i`. The absolute quoted path avoids dependence on
the working directory; type the underscores literally, without backslashes.
If `ls` or `sha256sum` cannot find the file, stop and send the output of
`pwd` and the failed command. The drop-in is scoped to audit6 and must be
installed first so dracut can stage firmware for built-in drivers.

Inspect the generated artifacts without changing boot selection:

```bash
sudo lsinitrd /boot/initrd.img-6.18.53-lockdown-t14g3-audit6 | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
sudo lsinitrd /boot/initrd.img-6.18.53-lockdown-t14g3-audit6 | grep -E 'regulatory[.]db([.]p7s)?$'
sudo sha256sum /boot/initrd.img-6.18.53-lockdown-t14g3-audit6 /boot/grub/grub.cfg
sudo grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit[36]|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
sudo grub-editenv /boot/grub/grubenv list
sudo cat /sys/class/firmware-attributes/thinklmi/attributes/ThunderboltAccess/current_value
```

Also run these unprivileged checks and send their output with the commands
above. The certificate is public, although the private signing key is not:

```bash
sha256sum /boot/vmlinuz-6.18.53-lockdown-t14g3-audit6 /boot/config-6.18.53-lockdown-t14g3-audit6
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIMEOUT)=' /etc/default/grub
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit6'
```

**Historical preboot hold point (passed on 28 September):** The initramfs listing must include
both signed regulatory-database files, early graphics/Wi-Fi/audio firmware,
microcode, and the LUKS/LVM root path. The GRUB menu must retain stock and
audit3 entries with stock 34 as normal default. If `grub-editenv` prints the
historical `hostdisk` warning, its `next_entry` read-back is untrusted. Do
not use `grub-reboot` for this trial.

## Stage B — runtime and physical validation

Audit6 has reached login on boot ID
`b9c5217f-03c3-47d6-b2b9-f1463d796984`. The running audit3 kernel was
previously demonstrated as a working custom rollback. Stock
`7.0.0-34-generic` remains installed and configured as the normal default,
but has not been demonstrated in a runtime boot. The old stock 31 entry is
gone. Test stock 34 separately before relying on it for recovery. For any
further audit6 boot test, select it manually from the visible GRUB menu and
keep physical access and the LUKS recovery passphrase available.

The owner reports keyboard, TrackPoint, touchpad, brightness, speaker playback,
microphone response in the GNOME input meter, direct USB-C display, USB storage,
and HDMI passing. A diskless QEMU machine reported `kvm support: enabled`;
a real VM guest remains untested.

After login on audit6, collect:

```bash
uname -r
cat /sys/kernel/security/lockdown
mokutil --sb-state
findmnt -no SOURCE,FSTYPE /
swapon --show
lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS
nproc
systemctl --failed
findmnt -t squashfs | head
ip -brief link
ls -l /dev/kvm
sudo journalctl -b -k --no-pager | grep -Ei 'secure boot|lockdown|dmar|iommu|tpm|i915|mt7921|sof|hda|nvme|ext4|mtd|nandsim|wpan|error|warning'
```

The built-in microphone passed the owner's GNOME input level test.
The headphone jack is outside the owner's requirements and has not been
tested. Ethernet is disabled in BIOS and is not an active-use requirement.
Test s2idle suspend/resume while physically present;
recheck display, input, Wi-Fi, audio, and charging afterward. Verify KVM can
open `/dev/kvm` with the intended VM workflow, not merely that the node
exists. Record the boot ID (`cat /proc/sys/kernel/random/boot_id`) and all
failures or untested items. A later normal reboot and successful root unlock
are required before declaring the stock default path validated; audit3 remains
the previously demonstrated custom rollback. Do not infer battery improvement
from a smaller image.
