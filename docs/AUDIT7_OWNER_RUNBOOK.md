# Audit7 owner-run installation and supervised boot

Target: `6.18.53-lockdown-t14g3-audit7`, package version `6.18.53-15`.
Audit7 is a separate candidate built from the booted audit6 config. It removes
AMD audio, simulated Wi-Fi, i915 GVT-g GPU sharing, and Xen KVM guest support.
Intel KVM remains. A successful build or image signature does not establish
that audit7 is installed or boots.
The verified signed-package SHA-256 is
`e524b0e621c0a3cd80ace944352dec04db6050e451ee6e8d07438bfc9c4ffdce`.
Do not install if the local digest differs.

Keep the working audit6 and audit3 kernels installed. Keep stock Ubuntu
`7.0.0-34-generic` as the configured default; its own successful runtime boot
has not been evidenced. Leave swap unchanged. Do not use `grub-reboot` while
the local `grub-editenv` hostdisk warning makes `next_entry` read-back uncertain.

## Stage A — signed package check and privileged installation

The package path below is absolute so the shell's current directory cannot
change which file is checked. Compare its SHA-256 with the expected digest in
the audit PDF before installing. If either the path or digest fails, stop.

```bash
ls -l -- '/home/the-ascended1/Lock_Down/build/audit7-final/signed/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb'
sha256sum -- '/home/the-ascended1/Lock_Down/build/audit7-final/signed/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb'
```

When the digest matches the audited value, run these one at a time. Stop and
send the complete output of any command that fails. Do not reboot just because
`dpkg` succeeds.

```bash
sudo install -m 0644 /home/the-ascended1/Lock_Down/config/60-lockdown-audit7-firmware.conf /etc/dracut.conf.d/60-lockdown-audit7-firmware.conf
sudo dpkg -i /home/the-ascended1/Lock_Down/build/audit7-final/signed/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb
sudo update-grub
sudo sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem /boot/vmlinuz-6.18.53-lockdown-t14g3-audit7
```

The exact-release dracut drop-in must precede `dpkg -i` so its post-install
initramfs includes early i915, MT7921U, Intel audio, and signed regulatory
database firmware. The package contains a signed kernel image, not a signed
Debian package container.

## Stage B — preboot hold point

Inspect the generated artifacts and recovery entries before manually selecting
audit7 from the visible GRUB menu. Send the output for review if anything is
missing or unexpected.

```bash
sudo lsinitrd /boot/initrd.img-6.18.53-lockdown-t14g3-audit7 | grep -E 'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
sudo lsinitrd -f etc/cmdline.d/20-crypt.conf /boot/initrd.img-6.18.53-lockdown-t14g3-audit7
sudo lsinitrd -f etc/crypttab /boot/initrd.img-6.18.53-lockdown-t14g3-audit7
sudo grep -E '(^set default=|^[[:space:]]*(menuentry|submenu) |6[.]18[.]53-lockdown-t14g3-audit[367]|7[.]0[.]0-34-generic)' /boot/grub/grub.cfg
grep -E '^GRUB_(DEFAULT|TIMEOUT_STYLE|TIMEOUT)=' /etc/default/grub
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit7'
```

The two regulatory files, firmware, microcode, LUKS UUID and matching crypttab
mapping must be present. The menu must retain audit6, audit3 and stock 34;
`GRUB_DEFAULT=0` must remain unchanged. If checks fail, boot a known-working
kernel and investigate instead of selecting audit7.

## Stage C — supervised audit7 runtime test

With physical access and the LUKS recovery passphrase available, manually
select audit7 once. After login, collect:

```bash
uname -r
cat /proc/sys/kernel/random/boot_id
cat /sys/kernel/security/lockdown
mokutil --sb-state
findmnt -no SOURCE,FSTYPE /
swapon --show
lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS
nproc
systemctl --failed
ip -brief link
ls -l /dev/kvm
sudo journalctl -b -k --no-pager | grep -Ei 'secure boot|lockdown|dmar|iommu|tpm|i915|mt7921|sof|hda|nvme|ext4|hwsim|error|warning'
```

Recheck keyboard, TrackPoint, touchpad, brightness, speakers and microphone,
Wi-Fi, USB storage, HDMI, and direct USB-C monitor. A real guest must boot with
the intended KVM workflow; mere access to `/dev/kvm` is not enough. Test
s2idle suspend/resume while physically present, then recheck display, input,
Wi-Fi, audio and charging. Record pass, fail or untested for each. The headphone
jack is outside the owner's requirements; Ethernet is disabled in BIOS.

Do not claim audit7 validated until these runtime and recovery checks pass.
No reduction in image size alone establishes improved battery life or security.
