# Audit10 owner-run installation and supervised boot

Status update, 29 September 2026: audit10 is signed, installed, and running.
The owner completed a supervised boot and a basic USB-storage read/copy/eject
check. The deterministic diskless KVM smoke passed twice; a real libvirt guest,
the remaining physical-device checklist, suspend/resume, and fallback/default
boot tests are not yet complete. Stages A-C below preserve the original
installation and boot instructions as a historical record; do not rerun
`dpkg -i` merely because they appear here.

Audit10 starts from the installed audit9 config and removes
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

## Stage A: owner-approved installation (completed)

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

## Stage B: preboot hold point (completed)

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

## Stage C: one supervised boot (initial boot completed)

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

## Verified runtime checkpoint and open tests

`dpkg-query` reports audit10 `6.18.53-18` installed. The installed
`/boot/config-6.18.53-lockdown-t14g3-audit10` matches the repository snapshot
at SHA-256 `121a6769868273d437d19d309a628793fabbec07f65e806568035740bd377f54`.
The installed kernel verifies against the existing MOK certificate. The
generated initramfs contains the expected LUKS UUID, LVM root, Intel
microcode, i915/SOF/MT7921U firmware, and regulatory database/signature.
GRUB still lists audit9 and stock Ubuntu 7.0.0-34; `GRUB_DEFAULT=0` was not
changed.

On the supervised audit10 boot, `uname -r` reported
`6.18.53-lockdown-t14g3-audit10`; the mapper-backed ext4 root mounted,
Secure Boot was enabled, lockdown selected `integrity`, all 12 logical CPUs
were available, MT7921U Wi-Fi connected, and `systemctl --failed` showed zero
system units. A SanDisk 0781:55a9 USB drive enumerated through UAS and mounted
as vfat. A 64 MiB file read succeeded; the owner copied screenshots and
reported a successful safe eject. The first insertion was deliberately
removed too quickly and logged a lost write; the drive had already reported
an improperly unmounted FAT volume. Do not call that FAT volume healthy, and
do not claim copied-file persistence until a later reinsert/read check.

`bash scripts/kvm-smoke.sh` passed 2/2 diskless guest initializations on the
running audit10 kernel. Host validation found KVM, `/dev/kvm`, vhost-net,
TUN, Intel DMAR/IOMMU and normal guest prerequisites available. The root-run
validator warned only that confidential-guest SEV/TDX support was unavailable;
an unprivileged run additionally warned about the cgroup devices check.
The owner-supplied `qemu-img check` found no errors in the existing audit9
qcow2 image. On 29 September, a separate audit10 qcow2 overlay was created
through a transient libvirt storage pool, backed by that audit9 image. A
transient 2-vCPU, 2-GiB KVM domain booted the Ubuntu 24.04.5 guest from the
overlay and existing NoCloud seed ISO. Its serial console reported
`Hypervisor detected: KVM`, reached `multi-user.target` and
`cloud-init.target`, and presented the `ttyS0` login prompt. The first launch
received a DHCP lease (`192.168.122.174/24`) and terminated after about 15
seconds; the second launch remained running until `virsh shutdown` caused a
clean domain exit. The second launch did not show a lease. The guest agent
did not connect on either launch (`guest-ping` failed). Thus real guest boot
and ACPI shutdown pass, but guest login, sustained networking, agent, and
application-level VM usability remain unverified. Do not call the complete
VM workflow a pass.

The test used the account's existing `libvirt` access, not `sudo`; the
transient pool has no autostart, and the transient domain no longer exists.
The overlay remains at
`/var/lib/libvirt/images/lockdown-audit10-vmtest-overlay.qcow2` for follow-up.
The base audit9 image's size and modification time remained unchanged. The
bounded creation/verification commands were:

```sh
virsh -c qemu:///system pool-create-as lockdown-audit10-test dir --target /var/lib/libvirt/images
virsh -c qemu:///system vol-create-as lockdown-audit10-test lockdown-audit10-vmtest-overlay.qcow2 3758096384 --format qcow2 --backing-vol /var/lib/libvirt/images/lockdown-audit9-vmtest.qcow2 --backing-vol-format qcow2
virt-install --connect qemu:///system --name lockdown-audit10-vmtest --virt-type kvm --import --transient --memory 2048 --vcpus 2 --cpu host-passthrough --osinfo generic --disk 'vol=lockdown-audit10-test/lockdown-audit10-vmtest-overlay.qcow2,bus=virtio' --disk 'path=/var/lib/libvirt/images/lockdown-audit9-vmtest-seed.iso,device=cdrom,format=raw,readonly=on' --network network=default,model=virtio --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 --graphics none --console pty --autoconsole text
virsh -c qemu:///system domblklist lockdown-audit10-vmtest --details
virsh -c qemu:///system net-dhcp-leases default
virsh -c qemu:///system qemu-agent-command lockdown-audit10-vmtest '{"execute":"guest-ping"}'
virsh -c qemu:///system shutdown lockdown-audit10-vmtest
```
