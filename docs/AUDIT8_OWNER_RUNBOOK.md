# Audit8 owner-run installation and supervised boot

Target release: `6.18.53-lockdown-t14g3-audit8`; package version `6.18.53-16`.
Audit8 starts from the booted audit7 resolved config and removes the unused
media/capture and IR-remote cores. Intel KVM, i915/HDMI/USB-C display, SOF/HDA
audio, real touchpad, MT7921U Wi-Fi, USB storage, and the LUKS/LVM/ext4 root
path are retained. A signed package and static checks do not prove audit8 boots.
The verified final signed-package SHA-256 is
`f7c722e63ea6fd32fb5ee92964c4681a59e05bbd5eb12acf3528d7539d64ff77`.
Do not install if your local digest differs.

Keep audit7, audit6, audit3, and the stock Ubuntu kernel installed. Leave swap
and `GRUB_DEFAULT=0` unchanged. Because local `grub-editenv` read-back has shown
a hostdisk warning, use the visible GRUB menu instead of `grub-reboot` for this
trial. The existing private MOK key is not installed or copied by these steps.

## Stage A: package digest and privileged installation

Run this read-only command from any working directory and compare it with the
verified digest recorded in the audit PDF before continuing:

```bash
sha256sum -- '/home/the-ascended1/Lock_Down/build/audit8-final/signed/linux-image-6.18.53-lockdown-t14g3-audit8_6.18.53-16_amd64.deb'
```

Only if the digest matches, run these one at a time. Stop and send the full
output of any command that fails. Do not reboot merely because `dpkg` succeeds.

```bash
sudo install -m 0644 /home/the-ascended1/Lock_Down/config/60-lockdown-audit8-firmware.conf /etc/dracut.conf.d/60-lockdown-audit8-firmware.conf
sudo dpkg -i /home/the-ascended1/Lock_Down/build/audit8-final/signed/linux-image-6.18.53-lockdown-t14g3-audit8_6.18.53-16_amd64.deb
sudo update-grub
sudo sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem /boot/vmlinuz-6.18.53-lockdown-t14g3-audit8
```

The exact-release dracut drop-in must precede `dpkg -i` so its post-install
initramfs contains the required early firmware. The EFI kernel inside the
package is signed; the Debian package container is not cryptographically
signed.

## Stage B: preboot hold point

Inspect the generated initramfs and recovery entries before manually choosing
audit8. The LUKS UUID must be `6dc6712f-ec48-4782-a37a-9cef06b82a0d`, and
the root LV must be `ubuntu-vg/ubuntu-lv`.

```bash
sudo lsinitrd /boot/initrd.img-6.18.53-lockdown-t14g3-audit8 | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
sudo lsinitrd -f etc/cmdline.d/20-crypt.conf /boot/initrd.img-6.18.53-lockdown-t14g3-audit8
sudo lsinitrd -f etc/crypttab /boot/initrd.img-6.18.53-lockdown-t14g3-audit8
sudo grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit[3678]|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIME)=' /etc/default/grub
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit8'
```

If any boot-critical item is missing or GRUB loses the audit7/audit6/stock
fallback, stop. Do not select audit8 until the discrepancy is resolved.

## Stage C: supervised audit8 boot

With physical access and the LUKS recovery passphrase available, manually
select audit8 under GRUB's Advanced options. After login, collect:

```bash
uname -r
cat /proc/sys/kernel/random/boot_id
cat /sys/kernel/security/lockdown
mokutil --sb-state
findmnt -no SOURCE,FSTYPE /
swapon --show
nproc
systemctl --failed
nmcli -t -f DEVICE,TYPE,STATE device status
ls -l /dev/kvm
find /sys/class/video4linux -mindepth 1 -maxdepth 1 -printf '%f\n'
```

The former fake vivid video/radio/touch nodes should be absent; `/dev/dri`
graphics devices should remain. Recheck keyboard, TrackPoint, touchpad,
brightness, speakers, microphone, Wi-Fi, USB storage, HDMI, and direct USB-C
display. Start a real KVM guest; `/dev/kvm` alone is insufficient. Test s2idle
suspend/resume while physically present, then recheck display, input, Wi-Fi,
audio, and charging. Record each as pass, fail, or untested. Headphone jack is
outside the owner's requirements; Ethernet is disabled in BIOS.

If audit8 fails to boot or loses a required device, use audit7 from GRUB and
send the failure details. Do not remove older kernels or change the stock
default. Smaller size is not a measured battery or security result.
