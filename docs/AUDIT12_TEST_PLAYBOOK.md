# Audit12 laptop test playbook

Target: `6.18.53-lockdown-t14g3-audit12`.
Status, 1 October 2026: the tests below are the remaining open items from
`docs/AUDIT12_OWNER_RUNBOOK.md`. Everything else listed there (first boot,
KVM smoke 2/2, real-guest login/network/DNS/workload/agent/shutdown,
owner-reported speakers/USB storage/USB Wi-Fi/mic/HDMI/USB-C/touchpad/
TrackPoint, one supervised s2idle cycle) is already recorded.

## Standing rules

- Keep the stock Ubuntu kernel as the GRUB default. Do not change
  `GRUB_DEFAULT`, `GRUB_TIMEOUT_STYLE`, or `GRUB_TIMEOUT`.
- Do not use `grub-reboot`. Select the audit12 entry manually from the
  visible 15-second menu.
- Do not deliberately trigger a kernel panic. Crash-dump checks are
  read-only (Test 9).
- For every test, record: date, current boot ID
  (`cat /proc/sys/kernel/random/boot_id`), the exact command or action,
  and the observed result. Paste the evidence into
  `docs/AUDIT12_OWNER_RUNBOOK.md` under a dated heading. An unrecorded
  test did not happen.

## Test 1: Firefox functional

Goal: the project's acceptance criteria require Firefox to keep working.

1. Boot audit12 from the GRUB menu. Confirm
   `uname -r` is `6.18.53-lockdown-t14g3-audit12`.
2. Launch Firefox from the desktop. Load two pages: one plain
   (e.g. `example.com`) and one media-heavy (any video page).
3. Play video for at least 60 seconds. Confirm audio plays and the
   picture does not tear or freeze.
4. Open `about:support`. Record the compositor and GPU process rows.

Pass: pages render, video plays with audio, no crash or GPU wedge in
`journalctl -p err -b` afterwards.

## Test 2: Steam functional

Goal: the project's acceptance criteria require Steam to keep working.

1. Launch Steam, sign in, let the library load.
2. Start the smallest installed game. Reach in-game rendering
   (menu counts; a full gameplay session is not required).
3. Quit the game and Steam cleanly.

Pass: client signs in, library renders, a game reaches rendered output,
no crash. If no game is installed, record that and install the smallest
available title; note the download size and time. Do not leave a large
download running as "the test".

## Test 3: keyboard

1. Open a terminal and a text editor.
2. Type every row of alphanumeric keys, then each modifier
   (Shift, Ctrl, Alt, Super) in combination with a letter.
3. Test the arrow keys.

Pass: every key registers the expected character or action.
Record any dead or mis-mapped key by name.

## Test 4: brightness and function keys

1. Press the brightness-up and brightness-down keys. Confirm the panel
   brightness visibly changes (or the OSD appears).
2. Press volume up/down/mute. Confirm the change takes effect.
3. Optionally run `bash scripts/check-intel-display.sh` and record
   its output.

Pass: brightness and volume keys produce their effect. Record exactly
which Fn keys work and which do nothing.

## Test 5: lid close/open and post-resume function

1. With audit12 running and Wi-Fi connected, close the lid.
   Wait 30 seconds. Open the lid.
2. Confirm the display lights on its own. If it does not, record that
   before touching anything else.
3. Confirm the touchpad moves the cursor and the TrackPoint/nub moves it.
4. Play audio (e.g. `speaker-test -t sine -f 440 -l 1`) and confirm sound.
5. Confirm Wi-Fi re-associates: `nmcli -t -f NAME,STATE c show --active`.

Pass: display, both pointing devices, audio, and Wi-Fi all work after
the lid cycle without a reboot. Record any device that needs manual
recovery and the exact recovery step.

## Test 6: USB storage persistence

1. Plug in a USB storage device. Copy a test file to it and record
   `sha256sum` of the file on the USB.
2. Safely eject (`udisksctl power-off -b /dev/sdX` with the correct
   device name), unplug the drive, wait 10 seconds.
3. Replug, remount, and `sha256sum` the file again.

Pass: the post-remount checksum matches the pre-eject checksum.

## Test 7: battery drain over a long suspend (unattended)

1. On AC power, record the starting state:
   `bash scripts/battery-report.sh`.
2. Unplug AC. Run `bash scripts/suspend-diagnostics.sh --do-suspend`
   and type the confirmation when prompted. The machine suspends.
3. Leave it suspended for at least 3 hours. Do not wake it early.
4. Wake, plug in AC, and run `bash scripts/battery-report.sh` again.

Pass criteria: none predefined. Record start percent, end percent,
elapsed time, and the computed drain rate. Do not extrapolate beyond
the measured window. One 9-second cycle already proved resume works;
this test measures drain, nothing else.

## Test 8: watchdog runtime (read-only)

Background: audit12 keeps `CONFIG_WATCHDOG`, `CONFIG_ITCO_WDT`, and
`CONFIG_SOFT_WATCHDOG`. The first-boot journal showed misc-device
conflicts and a possible legacy watchdog registration. None of this
has been functionally tested.

1. `journalctl -b | grep -i watchdog` and record every line.
2. `ls -l /dev/watchdog*` and record what exists.
3. `systemd-detect-virt` is not relevant here; instead confirm no
   watchdog daemon is configured to pet or reboot the machine
   (`systemctl list-units | grep -i watchdog`).

Pass: a written record of which watchdog devices exist, which driver
claimed them, and whether anything would reboot the machine on a
timeout. No functional timeout test is required or authorized.

## Test 9: crash-dump configuration (read-only)

1. Record whether `kdump-tools` (or equivalent) is installed and enabled:
   `systemctl is-enabled kdump-tools 2>/dev/null || true`.
2. Record `cat /sys/kernel/kexec_crash_loaded`.
3. Record the `crashkernel=` kernel command line, if any:
   `grep -o 'crashkernel=[^ ]*' /proc/cmdline || echo none`.

Pass: a written record of the crash-dump posture. Explicitly out of
scope: triggering a panic to test it.

## Test 10: GRUB recovery entries

1. `grep -c 'menuentry' /boot/grub/grub.cfg` and confirm entries exist
   for audit12, audit11, and stock Ubuntu.
2. Confirm `/etc/default/grub` still reads `GRUB_DEFAULT=0`,
   `GRUB_TIMEOUT_STYLE=menu`, `GRUB_TIMEOUT=15`.
3. `grub-editenv /boot/grub/grubenv list` and confirm `next_entry`
   is empty (no one-shot boot queued).

Pass: all three entries present, stock still the default, nothing
queued. Do this without rebooting.

## When the playbook is done

Every test above has a dated evidence entry in
`docs/AUDIT12_OWNER_RUNBOOK.md`. The remaining non-test work is
analysis, not laptop time: review the first-boot journal's legacy
probe noise (`hgafb`, `uvesafb`, GPIO and watchdog probes) before the
next pruning stage, for which `config/audit12-stage1-proposal.config`
already exists.
