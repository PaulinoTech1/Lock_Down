# Audit12 signing, installation, and initial-boot preparation

Status, 30 September 2026: audit12 is built, MOK-signed, installed, and has
passed its first basic boot.
Signed image SHA-256:
`ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d`.
Signed package SHA-256:
`3485262e37281c3b0b102fa62a86b2a95fbc694ada2f563225b0f59500544e35`.
Independent signature, embedded-config, and package-payload checks passed.
Live boot ID: `185290d8-83a0-4134-a3af-2173a3ffc147`. Secure Boot is enabled,
lockdown is in integrity mode, the current root is mapper-backed ext4, no
systemd units are failed, and swap remains `/swap.img` (8 GiB). Audit11 and
Ubuntu 7.0.0-34 remain installed as recovery choices.
The owner reports passing audit12 checks for speakers, USB storage, USB Wi-Fi,
microphone, HDMI, USB-C, touchpad, and TrackPoint/nub. This is owner-reported
hardware evidence; the headphone jack is intentionally out of scope. The
deterministic diskless KVM smoke test passed twice on audit12. It confirms the
host kernel can start and power off the fixture guest under KVM, not a real
guest's login, networking, agent, or workload.
Keep GRUB's visible 15-second menu and stock default. These instructions stop
before reboot; they do not use `grub-reboot` or remove fallback kernels.

## Stage A: sign the inner EFI image and repack the package (completed)

Run as the normal desktop user from any directory. `sbsign` may prompt in the
terminal for the MOK private-key passphrase. Do not paste that passphrase into
chat. The package container (`.deb`) is not cryptographically signed; the EFI
kernel image inside it is signed with the existing MOK.

```bash
set -euo pipefail
cd /home/the-ascended1/Lock_Down

release=6.18.53-lockdown-t14g3-audit12
unsigned="$PWD/build/audit12-final/unsigned/linux-image-${release}_6.18.53-1_amd64.deb"
signed_dir="$PWD/build/audit12-final/signed"
signed="$signed_dir/linux-image-${release}_6.18.53-1_amd64.deb"
expected_package=1e2a176d1cc070eaaade6a67ccaec80bf37822644ac46494596177ebe9485ce6
expected_config=444f72d745665f63acce59b7dce4fa9793140acbe56fd643deeb4aedf6dbc911
expected_unsigned_image=5ed81fa6b47706db5be3d2f109f11bbfe6ceb4decab123b526035082dd5c0d23

test "$(sha256sum "$unsigned" | cut -d' ' -f1)" = "$expected_package"
test "$(sha256sum build/audit12-final/unsigned/resolved.config | cut -d' ' -f1)" = "$expected_config"
test ! -e "$signed"
mkdir -p "$signed_dir"
stage=$(mktemp -d /tmp/audit12-sign.XXXXXXXX)
dpkg-deb --raw-extract "$unsigned" "$stage/package"
cmp -- build/audit12-final/unsigned/resolved.config \
  "$stage/package/boot/config-$release"
unsigned_signature=$(sbverify --list "$stage/package/boot/vmlinuz-$release" 2>&1 || true)
grep -Fqx 'No signature table present' <<< "$unsigned_signature"

bash scripts/sign-kernel.sh \
  --key /home/the-ascended1/.sb-keys/MOK.priv \
  --cert /home/the-ascended1/.sb-keys/MOK.pem \
  --kernel "$stage/package/boot/vmlinuz-$release" \
  --expected-sha256 "$expected_unsigned_image"

sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \
  "$stage/package/boot/vmlinuz-$release"
grep -Fv "  boot/vmlinuz-$release" "$stage/package/DEBIAN/md5sums" \
  > "$stage/md5sums"
mv -- "$stage/md5sums" "$stage/package/DEBIAN/md5sums"
(cd "$stage/package" && md5sum "boot/vmlinuz-$release" >> DEBIAN/md5sums)
dpkg-deb --build --root-owner-group "$stage/package" "$signed"

verify=$(mktemp -d /tmp/audit12-signed-check.XXXXXXXX)
dpkg-deb --extract "$signed" "$verify"
cmp -- build/audit12-final/unsigned/resolved.config \
  "$verify/boot/config-$release"
sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \
  "$verify/boot/vmlinuz-$release"
printf 'SIGNED_PACKAGE_SHA256 '
sha256sum "$signed"
printf 'SIGNED_IMAGE_SHA256 '
sha256sum "$verify/boot/vmlinuz-$release"
printf 'SIGNING_STAGE %s\n' "$stage"
```

Stop if any check fails. Record the printed signed package SHA-256; the next
stage requires it to be pasted into `expected=` below. The two `/tmp` staging
directories are retained for inspection and are not boot inputs.

## Stage B: install and inspect (completed; do not rerun blindly)

The signed package digest is pinned below. Run this block in your terminal. It installs the release-scoped
dracut firmware drop-in before `dpkg -i`, then verifies the installed image,
config, initramfs, LUKS metadata, GRUB entries, and recovery kernels. It does
not change `GRUB_DEFAULT`, schedule a one-shot boot, reboot, or remove kernels.

```bash
cd /home/the-ascended1/Lock_Down
sudo -v && sudo -n bash -euo pipefail <<'AUDIT12_INSTALL'
release=6.18.53-lockdown-t14g3-audit12
package=/home/the-ascended1/Lock_Down/build/audit12-final/signed/linux-image-6.18.53-lockdown-t14g3-audit12_6.18.53-1_amd64.deb
expected=3485262e37281c3b0b102fa62a86b2a95fbc694ada2f563225b0f59500544e35
test "$(sha256sum "$package" | cut -d' ' -f1)" = "$expected"
test "$(dpkg-deb -f "$package" Package)" = linux-image-6.18.53-lockdown-t14g3-audit12
test "$(dpkg-deb -f "$package" Version)" = 6.18.53-1
if dpkg-query -W -f='${db:Status-Abbrev}' "linux-image-$release" 2>/dev/null | grep -q ii; then
    echo "FAIL $release is already installed; stop and inspect state" >&2
    exit 1
fi

install -o root -g root -m 0644 \
  /home/the-ascended1/Lock_Down/config/60-lockdown-audit12-firmware.conf \
  /etc/dracut.conf.d/60-lockdown-audit12-firmware.conf
dpkg -i "$package"
update-grub

sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem "/boot/vmlinuz-$release"
cmp -- /home/the-ascended1/Lock_Down/config/candidate-6.18.53-lockdown-t14g3-audit12.config \
  "/boot/config-$release"
test -s "/boot/initrd.img-$release"
test "$(uname -r)" = 6.18.53-lockdown-t14g3-audit11
test "$(grep -E '^GRUB_DEFAULT=' /etc/default/grub)" = 'GRUB_DEFAULT=0'
test "$(grep -E '^GRUB_TIMEOUT_STYLE=' /etc/default/grub)" = 'GRUB_TIMEOUT_STYLE=menu'
test "$(grep -E '^GRUB_TIMEOUT=' /etc/default/grub)" = 'GRUB_TIMEOUT=15'

lsinitrd "/boot/initrd.img-$release" | grep -E \
  'microcode|crypt|lvm|rootfs-block|ext4|adlp_dmc|adlp_guc_70|tgl_huc|WIFI_RAM_CODE_MT7961|WIFI_MT7961_patch|sof-adl|sof-hda-generic|regulatory[.]db([.]p7s)?$'
crypt_cmdline=$(lsinitrd -f etc/cmdline.d/20-crypt.conf "/boot/initrd.img-$release")
crypttab=$(lsinitrd -f etc/crypttab "/boot/initrd.img-$release")
grep -F 'rd.luks.uuid=luks-6dc6712f-ec48-4782-a37a-9cef06b82a0d' <<< "$crypt_cmdline"
grep -F 'dm_crypt-0 /dev/disk/by-uuid/6dc6712f-ec48-4782-a37a-9cef06b82a0d none luks' <<< "$crypttab"

grep -E 'menuentry .*audit12|menuentry .*audit11|menuentry .*7[.]0[.]0-34-generic' /boot/grub/grub.cfg
dpkg-query -W 'linux-image-6.18.53-lockdown-t14g3-audit12' \
  'linux-image-6.18.53-lockdown-t14g3-audit11' 'linux-image-7.0.0-34-generic'
grub-editenv /boot/grub/grubenv list
systemctl --failed
echo 'PREBOOT HOLD: do not reboot until this complete output is reviewed.'
AUDIT12_INSTALL
```

The owner completed this stage and manually selected the audit12 normal menu
entry. It booted successfully to the encrypted root. `GRUB_DEFAULT=0` and the
visible 15-second menu remained unchanged; the stock kernel remains the default.
The environment read showed an empty `next_entry` (no one-shot boot was
scheduled) but also emitted hostdisk fallback warnings for
`hostdisk//dev/nvme0n1p2`. Do not use `grub-reboot`; retain manual menu
selection for future candidate boots.

The initramfs listing contained Intel microcode, crypt/LVM/rootfs/ext4 support,
the LUKS UUID and matching crypttab entry, required i915/MT7961/SOF firmware,
and both `regulatory.db` and `regulatory.db.p7s`. GRUB listed audit12,
audit11, and stock 7.0.0-34. The current boot's `systemctl --failed` was empty.

The kernel error-priority journal also contains nonfatal probe noise from
unused legacy framebuffer/platform drivers (`hgafb`, `uvesafb`, vendor GPIO
and watchdog probes). Multiple watchdog drivers report misc-device conflicts
and a possible legacy watchdog registration. Audit12 keeps `CONFIG_WATCHDOG`,
`CONFIG_ITCO_WDT`, and `CONFIG_SOFT_WATCHDOG`; crash-dump and watchdog runtime
behavior have not yet been functionally tested. These inherited-driver and
watchdog findings should be reviewed before the next pruning stage. The first
boot is only a basic-boot pass: physical hardware, real-guest,
suspend/resume, crash-dump, and fallback behavior remain open.

## Audit12 KVM smoke, 30 September 2026

The owner ran the project's unprivileged `bash scripts/kvm-smoke.sh` on the
running audit12 kernel. Both identical offline boots emitted the guest marker
and powered off cleanly (2/2). Recorded hashes:

```text
release:          6.18.53-lockdown-t14g3-audit12
kernel image:     ad7eb5c01f79049325a7b7c415c5c1c6ef10f8508429ae2eeb5ca8b340f33b2d
guest busybox:    df12634c17fcdca839ae5dc47d7627b7558511f7645de7c99ccf097a0f28ed5b
test initramfs:   bc75010a0af460d9a6b831d78fe6f9da7bf037dd641db813b0743926fe14f7b5
result:           KVM smoke PASS (2/2)
```

This is a diskless KVM initialization/power-off smoke only. It does not test a
real Ubuntu guest, guest login, network connectivity, guest agent, or workload.

## Audit12 real-guest KVM attempt and corrected command order

On 30 September 2026 the owner ran `virsh console lockdown-audit12-vmtest`
before the audit12 domain had been created or started. Libvirt returned
`failed to get domain 'lockdown-audit12-vmtest'`. This is not a guest boot
failure; it means no such domain existed, so audit12 real-guest testing has
not yet started. A later multiline heredoc paste produced no command output.
Read-only checks at that point found no audit12 VM process, domain, or overlay,
while the audit12 host kernel and default libvirt network were active. This is
consistent with the terminal still waiting for the heredoc terminator; the
terminal prompt must be checked to confirm that cause. If the terminal shows
the continuation prompt (`>`), press Ctrl+C to cancel that incomplete paste.

Use the project script below to create/start the transient domain. `sudo -v`
authenticates once; `sudo -n` runs the script without another prompt. The
script prints each phase, creates a new audit12 copy-on-write overlay without
modifying the audit9 base image, and stops if the overlay or domain already
exists, the guest network is inactive, or the base image/seed is absent.

```bash
cd /home/the-ascended1/Lock_Down
sudo -v && sudo -n bash scripts/audit12-vm-start.sh
```

The first audit12 start was later observed in the host journal: systemd
registered the guest at 21:48:45, libvirt's DHCP server gave it
`192.168.122.182` at 21:48:54, and the transient guest terminated at 21:49:01.
The separate overlay remains. At the next read-only check no audit12 domain or
QEMU process existed, so a DHCP lease alone must not be read as a currently
running VM. The audit11 test had a similarly short first launch before a
second launch reached its login prompt. To retry audit12 using this existing
overlay, run the explicit mode below. It verifies the overlay's qcow2 format,
backing path, and image consistency before starting the guest. It does not
create or overwrite an overlay.

```bash
cd /home/the-ascended1/Lock_Down
sudo -v && sudo -n bash scripts/audit12-vm-start.sh --existing-overlay
```

The second launch reached a serial login prompt and remained running. A
read-only check of the original NoCloud seed ISO found no guest user, password,
or SSH key configuration; it explicitly sets `ssh_pwauth: false`. The host
could not ping a QEMU guest agent, and the only DHCP lease still reflected the
first launch. The owner had no guest login credentials. The running transient
guest was asked to shut down through libvirt and disappeared from `virsh list`.
Login, sustained guest networking, agent response, and workload are still open.

To complete guest-login testing, use the separate disposable fixture below.
It prompts on the local terminal for a password of at least 12 characters for
guest account `audit12`, hashes it before creating a new NoCloud seed, and
creates a new overlay backed by the unchanged audit9 base. It does not alter
the first audit12 overlay or seed. The guest login password is distinct from
the host sudo password and must not be pasted into the audit or chat. The
script prints its progress and stops if any target already exists.

```bash
cd /home/the-ascended1/Lock_Down
sudo -v && sudo -n bash scripts/audit12-vm-login-test.sh && \
  sudo -n virsh -c qemu:///system console lockdown-audit12-login
```

At the serial console, log in as `audit12` with the password chosen at the
prompt. The seed explicitly requests DHCP for this guest's fixed virtual MAC.
After login, check `ip -br address`, `ip route`, gateway connectivity, DNS, and
a small guest workload. Detach from the serial console with Ctrl-]. From the
host, inspect `virsh net-dhcp-leases default` and try
`virsh qemu-agent-command lockdown-audit12-login '{"execute":"guest-ping"}'`;
record an unavailable agent separately. Request a clean guest shutdown with
`sudo -v && sudo -n virsh -c qemu:///system shutdown lockdown-audit12-login`,
then verify it is shut off. If login or networking does not work, preserve the
seed and overlay for diagnosis rather than rerunning or overwriting them.

## Audit12 login guest checkpoint, 30 September 2026

The owner reports successful serial-console login to the `audit12` guest
account. Read-only host checks confirmed the transient
`lockdown-audit12-login` domain is running with 2 vCPUs and 2 GiB of RAM, and
libvirt has assigned `192.168.122.59/24` to its fixed virtual MAC
`52:54:00:12:00:12`. The QEMU guest agent did not respond to `guest-ping`.
The password was entered locally and is not recorded here.

The owner then supplied guest-side results: `ens2` was up with
`192.168.122.59/24`, the default route used `192.168.122.1`, and a three-packet
ping to that gateway had zero loss. `getent ahostsv4 ubuntu.com` returned an
IPv4 address, establishing DNS resolution but not end-to-end internet access.
A 64 MiB zero-filled file was written and hashed; SHA-256
`3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351`
matches an independent host-side hash of 64 MiB of zeros. This is a bounded
guest storage/read/CPU workload pass. `systemctl is-active qemu-guest-agent`
reported `inactive`, and host-side guest-ping still did not connect. Clean
guest shutdown and agent behavior remain open.

The owner then updated the guest's Ubuntu package indexes and installed
`qemu-guest-agent` and its `liburing2` dependency. The package setup explained
that the service is a static unit, but the explicit start succeeded and
`systemctl is-active qemu-guest-agent` returned `active`. A fresh host-side
`guest-ping` returned `{"return":{}}`. The package download also exercised
outbound access to the configured Ubuntu repositories. Libvirt accepted a
graceful shutdown request for `lockdown-audit12-login`; the transient machine
terminated at 22:33:41 and `virsh list --all` became empty. The audit12 host
still reported zero failed systemd units. The separate test overlay and seed
remain available for inspection; the guest password is not recorded here.
This closes the planned audit12 guest login, local network, DNS, bounded
workload, guest-agent, and clean-shutdown checks for this disposable VM.

## Audit12 owner-reported hardware checks, 30 September 2026

The owner reports passing tests for speakers, USB storage, USB Wi-Fi,
microphone, HDMI, USB-C, touchpad, and TrackPoint/nub. These are owner-reported
results, not independently observed measurements. The headphone jack remains
out of scope. Keyboard, brightness/hotkeys, lid-close behavior, and USB
copied-file persistence were not included in this report. To confirm removable
storage persistence, safely eject, unplug/reconnect, and verify the copied
file's checksum after remounting.

The disposable real KVM guest checklist passed as recorded above. Remaining
physical checks include keyboard, brightness/function keys, lid close/open if
used, and post-resume display, touchpad/TrackPoint, and audio operation. Keep
the stock GRUB default and verify visible recovery entries; do not use the
currently unreliable `grub-reboot` one-shot path. Crash-dump configuration
may be inspected read-only, but do not deliberately trigger a kernel panic
for this validation. Ethernet is out of scope per owner (disabled in
firmware), and headphone-jack testing is not required.

## Audit12 supervised s2idle checkpoint, 30 September 2026

The first owner-initiated attempt was cancelled with Ctrl+C during the script's
five-second countdown. It did not enter suspend and is not counted as a test.
The second attempt printed `resumed.` and wrote pre-suspend and post-resume
snapshots under `/tmp/lockdown-suspend.tP09aJcw/`. The kernel journal records
`PM: suspend entry (s2idle)` at 22:40:51 and `PM: suspend exit` at 22:41:00,
about a nine-second cycle. No error-priority kernel messages appeared in that
window, and the host still runs audit12 with zero failed systemd units.

The immediate post-resume snapshot showed the MT7921U USB Wi-Fi adapter still
enumerated but its interface carrier temporarily down. NetworkManager and
wpa_supplicant logs show re-association, key negotiation, and a new DHCP lease
for `192.168.1.15` by 22:41:03. A later live check showed the Wi-Fi connection
`Paulino` active, carrier 1, and `192.168.1.15/24` assigned. The owner then
reported three successful pings to the gateway `192.168.1.1` (0% loss) and
successful DNS resolution of `ubuntu.com` to `185.125.190.29`. The snapshot
was taken before Wi-Fi recovery completed; it is not evidence of a persistent
Wi-Fi failure. The current evidence establishes one short s2idle suspend/resume
cycle and functional Wi-Fi recovery. Physical display, input, and audio
function after waking have not yet been owner-reported; no battery-drain claim
follows from this short cycle.
