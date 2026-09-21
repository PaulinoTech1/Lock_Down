# Suspend

Firmware reality: s2idle ONLY. Never attempt S3.

## Why s2idle only, and why forcing S3 is wrong

- Lenovo removed legacy S3 from the UEFI on this platform generation; the
  firmware exposes s2idle (Suspend-to-Idle) as the suspend mode. Forcing S3
  via kernel hacks (`acpi_sleep=s3_bios`, DSDT overrides, or `mem_sleep`
  writes the firmware does not advertise) fights the firmware's power
  sequencing instead of working with it.
- What goes wrong when S3 is forced on firmware that does not offer it:
  failed resume (black screen, hung EC), devices left in undefined power
  states, and in the worst case an EC/BIOS state that requires a full
  power drain to clear. The failure mode is a bricked-feeling machine that
  is actually just desynchronized firmware.
- Verify what the firmware exposes: `/sys/power/mem_sleep` shows the
  available modes in brackets, e.g. `[s2idle]`. If only s2idle is listed,
  that is the answer. Do not override it.
- Cost of s2idle vs S3: s2idle keeps more of the SoC powered, so idle
  drain is higher than classic S3 would be. That is the firmware's design;
  the correct response is measuring the drain and tuning wakeups, not
  fighting the firmware.
- Confidence: High that forcing S3 on non-offering firmware is wrong
  (documented failure class). Medium that this unit is s2idle-only until
  `/sys/power/mem_sleep` is read on the machine (Alder Lake ThinkPads of
  this generation are s2idle-only, but verify, do not assume).

## Suspend test matrix (LOCAL; run on the machine)

Each row: suspend to s2idle, resume, verify the subsystem. Record
pass/fail and dmesg evidence per row.

1. Basic suspend/resume: system enters s2idle, resumes on lid/power key,
   screen locks on resume, no kernel oops in dmesg.
2. Wi-Fi recovery (HIGHEST-RISK PATH, explicit): the external MediaTek
   MT7921U (0e8d:7961) is the only network path. After resume: device
   still enumerated on USB, driver rebound, association re-established,
   DHCP renewed, traffic flows. Failure here means no network until manual
   replug; test repeatedly, including rapid suspend/resume cycles.
3. Audio recovery: HDA/SOF devices present after resume, playback works,
   no stuck streams.
4. NVMe recovery: namespace still present, no I/O errors in dmesg, APST
   still enabled (re-run `check-nvme-power.sh` and compare).
5. Graphics recovery: display comes back at the right mode, no corruption,
   compositor responsive; compare `check-intel-display.sh` before/after.
6. USB recovery: all pre-suspend USB devices re-enumerated; the Wi-Fi
   adapter specifically (see row 2).
7. Battery drain measurement procedure:
   a. Charge to a known level, record `energy_now` (see
      `battery-report.sh`).
   b. Suspend to s2idle for a fixed window (e.g., 8 hours overnight).
   c. On resume, record `energy_now` again; compute drain rate (mW).
   d. Repeat at least 3 nights; report the median. A single night is
      anecdote, not data.
   e. Investigate wakeups if drain is high: check wake sources
      (`/sys/kernel/debug/wakeup_sources` where readable) and disable
      spurious wakeups (USB wakeup on the Wi-Fi adapter is a usual
      suspect; tune per-device `power/wakeup`, never globally).

## suspend-diagnostics.sh

`scripts/suspend-diagnostics.sh` gathers pre/post suspend state WITHOUT
triggering suspend itself, unless `--do-suspend` is passed WITH an
explicit confirmation prompt. Rationale: a diagnostics script that
suspends the machine as a side effect is a footgun in automated runs.

What it collects (pre-suspend, and post-suspend when run again after
resume):

- Timestamp and `/sys/power/mem_sleep` contents.
- dmesg timestamps where readable (degrades gracefully under
  `dmesg_restrict`; run with sudo for full output).
- USB device list (bus/port/VidPid, no serials).
- Network interface presence and carrier state (interface names only, no
  SSIDs, no MACs, no IPs).
- NVMe namespace presence.
- Audio device presence (card list).
- DRM connector status.

With `--do-suspend`: prompts for typed confirmation, then writes
`s2idle` (or the firmware's advertised default) to
`/sys/power/mem_sleep`, collects the pre-state, triggers suspend via
`/sys/power/state`, and on resume collects the post-state and diffs.
The confirmation is mandatory; there is no `--yes` flag, by design.

## Recovery from failed suspend

- Failed resume with black screen: hold power to force off, boot, check
  dmesg from the previous boot (`journalctl -b -1`) for the suspend path.
- Repeated resume failures on a subsystem: that subsystem goes in the
  test matrix as a known issue with its workaround (e.g., a resume hook
  that unbinds/rebinds the MT7921U driver), documented, not silently
  scripted around.
- Never "fix" suspend by disabling suspend. An untested suspend path is
  how machines get left unlocked and draining; test it instead.
