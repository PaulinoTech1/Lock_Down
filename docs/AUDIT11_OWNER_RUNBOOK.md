# Audit11 owner install and supervised validation

Status, 30 September 2026: audit11 is **built, MOK-signed, installed, and
running**. Its basic boot checks, two diskless KVM boots, and a real guest
boot to serial login followed by ACPI shutdown passed. Physical hardware,
guest login/network/agent/workloads, suspend/resume, and fallback remain
untested. The build used the committed audit10 effective config plus exactly
three `y`-to-`n` cuts and a
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
HDMI, USB storage, complete VM use, suspend/resume, crash diagnostics, and an actual
fallback/default reboot remain untested on audit11. Keep the stock and audit10
fallbacks; do not infer a power or exploit-mitigation magnitude from three
disabled options.

## KVM and real-guest checkpoint, 30 September 2026

The running audit11 release was `6.18.53-lockdown-t14g3-audit11`. Its effective
config has `CONFIG_KVM=y`, `CONFIG_KVM_INTEL=y`, `CONFIG_TUN=y`, and
`CONFIG_VHOST_NET=y`. `virt-host-validate qemu` passed VMX, `/dev/kvm`,
vhost-net, TUN, and Intel DMAR/IOMMU checks. It warned about the cgroup
`devices` controller and unavailable confidential-guest SEV/TDX support;
neither warning prevented this ordinary KVM guest from starting. The fixed,
unprivileged `bash scripts/kvm-smoke.sh` test passed both boots and clean
power-offs. It recorded the host kernel SHA-256
`c78f8b73538b9e0c5f488f82e93b4794e2a06934c667e624f326f5d27de7f3c6`
and deterministic initramfs SHA-256
`bc75010a0af460d9a6b831d78fe6f9da7bf037dd641db813b0743926fe14f7b5`.

No libvirt domain was active before the test. A new transient libvirt pool and
`lockdown-audit11-vmtest-overlay.qcow2` were created; the audit9 base image was
not mounted for writing. The first transient 2-vCPU, 2-GiB guest launch obtained
a DHCP lease at `192.168.122.215/24` and exited after about 16 seconds. A
second launch from the overlay was attached to the serial console: the Ubuntu
24.04.5 guest reported `Hypervisor detected: KVM`, reached `multi-user.target`
and `cloud-init.target`, and presented its `ttyS0` login prompt. It remained
running until `virsh shutdown` requested an ACPI shutdown. Libvirt then
showed no active domains or failed host units. The audit9 base image retained
its pre-test size (625612288 bytes) and modification time (1790669371);
the audit11 overlay remains for follow-up. No sudo authentication was used.

The second launch showed its guest NIC down in cloud-init's console output;
there was no DHCP lease for its MAC. `guest-ping` did not connect to a guest
agent. Guest login, sustained networking, agent, and application workloads
therefore remain **open**; reaching a login prompt is not a complete VM pass.
The base image could not be directly rechecked with `qemu-img check` from this
unprivileged shell (`Permission denied`); its earlier audit10 integrity check
and unchanged size/mtime are recorded separately, not substituted for a fresh
integrity check.

```bash
bash scripts/kvm-smoke.sh
virt-host-validate qemu
virsh -c qemu:///system pool-create-as lockdown-audit11-test dir --target /var/lib/libvirt/images
virsh -c qemu:///system vol-create-as lockdown-audit11-test lockdown-audit11-vmtest-overlay.qcow2 3758096384 --format qcow2 --backing-vol /var/lib/libvirt/images/lockdown-audit9-vmtest.qcow2 --backing-vol-format qcow2
virt-install --connect qemu:///system --name lockdown-audit11-vmtest --virt-type kvm --import --transient --memory 2048 --vcpus 2 --cpu host-passthrough --osinfo generic --disk 'vol=lockdown-audit11-test/lockdown-audit11-vmtest-overlay.qcow2,bus=virtio' --disk 'path=/var/lib/libvirt/images/lockdown-audit9-vmtest-seed.iso,device=cdrom,format=raw,readonly=on' --network network=default,model=virtio --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 --graphics none --console pty --autoconsole text
virsh -c qemu:///system shutdown lockdown-audit11-vmtest
```

The pool and overlay now exist; the creation commands above document the
completed test and must not be rerun blindly. Follow-up should inspect the
seed/network configuration and use the retained overlay or a separately named
fresh overlay after confirming the intended test scope.
