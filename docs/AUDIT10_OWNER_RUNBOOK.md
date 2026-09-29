# Audit10 owner-run installation and supervised boot

Audit10 is a **signed, statically checked package**, not an installed or
boot-validated kernel. It starts from the running audit9 config and removes
28 specialty USB, USB test, and legacy USB-storage helper options. The
resolved config differs from audit9 only in those 28 `y`-to-`n` values and
the release name. Generic USB mass storage, UAS, xHCI, HID, MT7921U Wi-Fi,
Intel KVM, i915/USB-C/HDMI, root unlock, Snap, and crash diagnostics remain.
Some old readers/bridges may lose functionality; do not assume all future
USB storage devices work merely because the class drivers remain.

Target release: `6.18.53-lockdown-t14g3-audit10`; package version
`6.18.53-18`. The signed image package is:

```text
/home/the-ascended1/Lock_Down/build/audit10-final/signed/linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb
```

Its SHA-256 is
`8a98c461cdb4ba96e52b24ccb958100763ff2e7485cb3dcb9399fbecbff2ed44`.
The EFI kernel image *inside* that package is MOK-signed; the `.deb`
container itself is not cryptographically signed. Keep audit9 and the stock
Ubuntu kernel installed. Do not remove older kernels, change swap, or change
`GRUB_DEFAULT=0` for this trial. Do not use `grub-reboot`: the prior local
GRUB environment read-back showed a hostdisk warning. Use the visible GRUB
menu for a supervised trial.

## Stage A: owner-approved installation

First compare the exact package digest. Stop if it differs:

```bash
sha256sum -- '/home/the-ascended1/Lock_Down/build/audit10-final/signed/linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb'
```

Only when you are ready to install audit10, run these from any working
directory, one at a time. Send the complete output of any failed command.
The release-specific dracut drop-in must be installed *before* `dpkg -i`
so the package's post-install initramfs receives early firmware.

```bash
sudo install -m 0644 '/home/the-ascended1/Lock_Down/config/60-lockdown-audit10-firmware.conf' '/etc/dracut.conf.d/60-lockdown-audit10-firmware.conf'
sudo dpkg -i '/home/the-ascended1/Lock_Down/build/audit10-final/signed/linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb'
sudo update-grub
sudo sbverify --cert '/home/the-ascended1/.sb-keys/MOK.pem' '/boot/vmlinuz-6.18.53-lockdown-t14g3-audit10'
```

Do not reboot merely because installation succeeds.

## Stage B: preboot hold point

Check the generated initramfs and fallback menu before selecting audit10.
The LUKS UUID must be `6dc6712f-ec48-4782-a37a-9cef06b82a0d` and the
root LV must be `ubuntu-vg/ubuntu-lv`.

```bash
sudo lsinitrd '/boot/initrd.img-6.18.53-lockdown-t14g3-audit10' | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
sudo lsinitrd -f etc/cmdline.d/20-crypt.conf '/boot/initrd.img-6.18.53-lockdown-t14g3-audit10'
sudo lsinitrd -f etc/crypttab '/boot/initrd.img-6.18.53-lockdown-t14g3-audit10'
sudo grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit(9|10)|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIME)=' /etc/default/grub
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit10' 'linux-image-6.18.53-lockdown-t14g3-audit9' 'linux-image-7.0.0-34-generic'
```

Stop if a boot-critical component is missing, the LUKS UUID differs, the
regulatory database or firmware is absent, or GRUB loses audit9/stock
fallbacks. Share the output for review before booting audit10.

## Stage C: one supervised boot

With physical access and the LUKS recovery passphrase available, manually
select audit10 under GRUB's Advanced options. After login:

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
```

Recheck keyboard, TrackPoint, touchpad, brightness, speakers, microphone,
MT7921U Wi-Fi, USB storage, HDMI, and direct USB-C display. Test a real KVM
guest with the intended networking/guest-agent setup; `/dev/kvm` alone is
not sufficient. Test s2idle suspend/resume while physically present, then
recheck input, display, Wi-Fi, audio, and charging. Record each item as pass,
fail, or untested. If audit10 fails to boot or a required device stops
working, select audit9 or stock Ubuntu from GRUB and preserve the failure
logs. Static package verification is not a substitute for this boot test.
