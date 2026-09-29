# Audit3 supervised boot checklist

Target: `6.18.53-lockdown-t14g3-audit3`. Record actual results and the boot ID;
static package checks do not count as a successful boot. Keep the stock Ubuntu
kernel as GRUB default and do not remove the failed audit2 entry during this test.
Do not change `/swap.img`.

## Hold point before selecting the candidate

- [x] Installed `/boot/vmlinuz-6.18.53-lockdown-t14g3-audit3` has a valid MOK
  signature (`sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem ...`).
- [x] Generated `/boot/initrd.img-6.18.53-lockdown-t14g3-audit3` exists; inspect
  it with `lsinitrd` for the correct LUKS UUID/crypttab, LVM and ext4 support,
  compressed Intel i915 and MediaTek MT7921U firmware, and microcode.
  **Static check passed, 24 September:** rebuilt image hash
  `de381c6969713e94ea2200cafbe9a869ae217076f4f87478e3bebc50de55ff7d`
  includes the three i915 files, both MT7961 files, SOF firmware with its
  symlink target and three HDA topologies. Correct root settings and microcode
  remain present. The earlier firmware-deficient image is preserved at
  `/boot/initrd.img-6.18.53-lockdown-t14g3-audit3.before-firmware`.
  This permits the supervised test; it does not prove successful firmware loading.
- [x] `/boot/grub/grub.cfg` contains both audit3 and stock
  `7.0.0-31-generic` entries. `/etc/default/grub` still says
  `GRUB_DEFAULT=0`, `GRUB_TIMEOUT_STYLE=menu`, and `GRUB_TIMEOUT=15`.
  Supplied generated configuration confirms default 0 selects stock
  `7.0.0-34-generic`, with empty `next_entry`.
  Keep 31 available as the known-good fallback. Collect root-only evidence with
  `sudo bash /home/the-ascended1/Lock_Down/scripts/inspect-audit3-boot.sh`.
- [ ] Have physical access and a known-good way to select the stock kernel.
  Select audit3 manually from the visible GRUB menu. Latest local-sudo
  `grub-editenv` read-back has no historical `hostdisk` warning, but no one-shot
  is queued and one-shot behavior has not been tested.

## One candidate boot (record pass, fail, or not tested for each)

- [x] GRUB selected audit3; LUKS passphrase prompt and LVM root unlock worked;
  local login completed without emergency mode.
- [x] `uname -r` is exactly `6.18.53-lockdown-t14g3-audit3`; boot ID is
  `7c6b86be-90b4-42cf-9fb1-a7c33d0674b6`.
- [x] `mokutil --sb-state` says enabled; running lockdown state at
  `/sys/kernel/security/lockdown` includes `[integrity]`; AppArmor is active.
  A valid image signature alone is not proof of runtime lockdown.
- [ ] `nproc` reports all 12 logical CPUs. `findmnt /` shows the LUKS/LVM ext4
  root; EFI filesystem mounts with CP437. `swapon --show` still shows
  `/swap.img` on the encrypted root, unchanged. Runtime confirms 12 CPUs, the
  LUKS/LVM ext4 root, `/boot/efi` as vfat with `codepage=437`, and unchanged
  `/swap.img`.
- [ ] TPM2 device and expected Intel microcode are visible; inspect the journal
  for VT-d/IOMMU and interrupt-remapping activation. Confirm NVMe is healthy
  and the root filesystem has no new I/O or ext4 errors. TPM2, microcode
  `0x43b`, and DMAR/IRQ remapping are confirmed. NVMe health testing remains.
- [ ] Keyboard, TrackPoint, touchpad, internal display, and brightness keys
  work. Inspect i915 DMC/GuC/HuC firmware messages and ensure there is no GPU
  wedge. Physically test HDMI and USB-C DisplayPort outputs if available.
- [ ] External MT7921U Wi-Fi associates and passes a network test; inspect its
  firmware messages. Firmware initialization and association to `Technocopia`
  with a default route are confirmed; a ping to local gateway succeeded with
  0% packet loss. Broader network throughput/application testing remains.
  Test any required USB Ethernet dongle separately.
- [ ] Speakers, microphone, and headphone path work on the SOF/HDA/ALC257
  stack. USB-C role/charging/DP behavior is checked for UCSI errors.
- [ ] Snap images mount (loop plus SquashFS); inspect `systemctl --failed`
  and relevant mount units. The supplied output reports zero failed systemd
  units; actual Snap SquashFS mounts through loop devices are confirmed.
- [ ] Confirm the actual Thunderbolt/USB4 state with `boltctl list`,
  `lspci -k`, and the kernel journal. `CONFIG_USB4=n` alone is not proof that
  PCI controllers are disabled in firmware.
- [ ] Perform one supervised s2idle suspend/resume; verify display, input,
  Wi-Fi, audio, and battery/charging afterward. Never attempt S3 on this host.
- [ ] Inspect the full candidate boot journal for new errors and record each
  unresolved item. Do not call the candidate validated while required paths
  fail or remain untested.
  Known warning: built-in `CONFIG_MTD_NETtel=y` probes nonexistent SnapGear
  flash and raises an `ioremap on RAM` kernel warning. Recurring `wpan0`-`wpan3`
  encryption errors come from enabled IEEE 802.15.4 fake/test radios. Exclude
  those unused drivers in a separately gated build before final validation.

## Recovery and follow-up

- [ ] Reboot normally and verify the stock Ubuntu kernel remains the default
  and can boot and unlock the same root. Record its boot ID and `uname -r`.
- [ ] Only after functional validation, compare stock and audit3 power data
  under matched workloads and firmware/userspace conditions; do not infer
  battery gains from Kconfig alone.
