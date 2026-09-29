# Audit9 owner-run installation and supervised boot

Status update, 29 September 2026: audit9 is already installed and running.
The installation hold below records the original staged procedure; do not
repeat `dpkg -i` solely because this historical runbook says to install it.
The owner reports required physical hardware working. A full libvirt guest,
s2idle suspend/resume, and fallback/default checks remain open.

Target release: `6.18.53-lockdown-t14g3-audit9`; package version `6.18.53-17`.
Audit9 starts from audit8's resolved config and removes unused USB gadget,
serial/ACM/printer/NIC, touchscreen-device, alternate network-protocol,
industrial-I/O, VM-GPU, and inactive-LSM families. The actual I2C touchpad
uses `hid-multitouch`, which remains built in. Intel KVM, xHCI USB host,
USB storage, MT7921U Wi-Fi, i915/USB-C/HDMI, SOF/HDA, root unlock, Snap,
and crash-dump support remain. A signed package and static checks do not
prove audit9 boots or that a real VM works.

**Hold:** audit8 has not been booted. First install and supervised-boot audit8
using [AUDIT8_OWNER_RUNBOOK.md](AUDIT8_OWNER_RUNBOOK.md); record its hardware,
real-guest, suspend, and fallback results. Do not install audit9 over an
unvalidated audit8 step. Leave audit7, audit6, audit3, and the stock Ubuntu
kernel installed. Leave swap and `GRUB_DEFAULT=0` unchanged. Do not use
`grub-reboot`: its local `grub-editenv` read-back previously showed a hostdisk
warning. Use the visible GRUB menu for a supervised trial.

## Stage A: digest and privileged installation

The final signed-package SHA-256 is
`9d19f9937495ad975ca5859e38af6f35f69426a4eaea3717341f49dafaf9e5ea`.
Stop if the local
digest differs. Run the following from any working directory:

```bash
sha256sum -- '/home/the-ascended1/Lock_Down/build/audit9-final/signed/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb'
```

Only after audit8's supervised checks pass and the audit9 digest matches,
run these one at a time. Send the full output of any failure. Do not reboot
merely because `dpkg` succeeds.

```bash
sudo install -m 0644 '/home/the-ascended1/Lock_Down/config/60-lockdown-audit9-firmware.conf' '/etc/dracut.conf.d/60-lockdown-audit9-firmware.conf'
sudo dpkg -i '/home/the-ascended1/Lock_Down/build/audit9-final/signed/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb'
sudo update-grub
sudo sbverify --cert '/home/the-ascended1/.sb-keys/MOK.pem' '/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9'
```

The exact-release dracut drop-in must precede `dpkg -i` so its post-install
initramfs includes early firmware. The EFI kernel inside the package is
MOK-signed; the Debian package container is not cryptographically signed.

## Stage B: preboot hold point

Check the generated initramfs and recovery entries before selecting audit9.
The LUKS UUID must be `6dc6712f-ec48-4782-a37a-9cef06b82a0d`, and the
root LV must be `ubuntu-vg/ubuntu-lv`.

```bash
sudo lsinitrd '/boot/initrd.img-6.18.53-lockdown-t14g3-audit9' | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
sudo lsinitrd -f etc/cmdline.d/20-crypt.conf '/boot/initrd.img-6.18.53-lockdown-t14g3-audit9'
sudo lsinitrd -f etc/crypttab '/boot/initrd.img-6.18.53-lockdown-t14g3-audit9'
sudo grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit[36789]|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIME)=' /etc/default/grub
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit9'
```

If a boot-critical item is missing or GRUB loses audit8/audit7/stock
fallbacks, stop. Do not select audit9 until the discrepancy is resolved.

## Stage C: supervised audit9 boot

With physical access and the LUKS recovery passphrase available, manually
select audit9 under GRUB's Advanced options. After login, collect:

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
udevadm info --attribute-walk --name=/dev/input/event12 | grep -E 'hid-multitouch|i2c_hid_acpi'
```

The input event number may change; find the live touchpad event with
`grep -A5 'SYNA8018.*Touchpad' /proc/bus/input/devices` if event12 is no
longer the touchpad. Recheck keyboard, TrackPoint, touchpad, brightness,
speakers, microphone, MT7921U Wi-Fi, USB storage, HDMI, and direct USB-C
display. Start a real KVM guest with the intended network and guest-agent
workflow: `/dev/kvm` alone does not prove it works. Audit9 deliberately drops
VSOCK and USB Ethernet, so report any VM integration or recovery-network
workflow that needs them. Test s2idle suspend/resume while physically
present, then recheck input, displays, Wi-Fi, audio, and charging. Record
each as pass, fail, or untested.

If audit9 fails to boot or loses a required device, use audit8 or audit7 from
GRUB and send the failure details. Do not remove older kernels or change the
stock default. A smaller config is not a measured battery or security result.
