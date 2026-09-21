# Testing

Two kinds of tests: runnable local checks in `tests/` (safe to run
anywhere, including CI, because they only parse repo files or skip when
hardware is absent) and hardware test matrices (LOCAL only, run on the
machine). CI must not pretend to run hardware tests.

## Runnable local checks (tests/)

- `tests/test-sysctl-values.sh`: verifies `sysctl/99-workstation-hardening.conf`
  parses (no syntax errors), has no duplicate keys, and every assignment
  line carries the required `key=value` shape. Pure file parsing; runs in CI.
- `tests/test-nft-syntax.sh`: if `nft` is available, validates the nftables
  rule files' syntax with `nft --check`; if `nft` is absent, skips with a
  clear message (skip is not failure). Runs in CI when nft exists.
- Both scripts are LOCAL-safe: they never touch live system state.

## Hardware test matrices (LOCAL only)

All of the following run on the ThinkPad itself. Each row records
pass/fail, the command used, and the evidence (log excerpt, sysfs value).
A matrix row without recorded evidence is not a pass.

### Boot matrix

- Secure Boot on, custom kernel: boots (signature verifies under enrolled
  keys).
- Secure Boot on, unsigned module load attempt: rejected.
- Secure Boot off: boots (documented degraded state, not a target state).
- Distro rescue kernel: boots from the boot menu.
- Previous known-good custom kernel: boots (fallback exists).

### Storage matrix

- LUKS unlock with passphrase: works.
- LUKS unlock with TPM2+PIN (if provisioned): works.
- LUKS unlock with recovery passphrase: works (tested on a scratch
  mapping; the real recovery passphrase is never typed into a test log).
- Offline unreadability: volume removed and attached to another machine
  (or booted from live media): data unreadable without credentials.

### PAM matrix

- Password + YubiKey at SDDM: works.
- Password + YubiKey at TTY: works.
- Password + YubiKey for sudo in KDE session: works.
- Negative cases: wrong password rejected; YubiKey absent rejected; wrong
  PIN rejected; removed key rejected. Each negative case must actually be
  attempted and logged, not assumed.

### KVM matrix

- `scripts/check-iommu.sh`: passes (VT-d + interrupt remapping active).
- Guest boots under each profile in `vm-profiles/`.
- Isolation checks per profile: untrusted guest cannot reach host LAN,
  cannot see host filesystems, has no clipboard channel, has no USB
  redirect devices; sVirt label applied (`ps -Z` / AppArmor status shows
  the confined label).
- Isolated network behavior: guest on `untrusted-isolated` gets DHCP, can
  reach the NAT gateway, cannot reach other zones (verify with the
  nftables counters/logs, not by assumption).

### Power matrix

- Active power profile applied: EPP and platform profile read back the
  expected values under each of battery/balanced/AC-performance.
- APST active: `scripts/check-nvme-power.sh` shows APST enabled.
- Deep C-states reachable: package C10 observed at idle (turbostat or
  equivalent, short sample).
- Suspend/resume: the full matrix in docs/SUSPEND.md, including the
  Wi-Fi recovery row (highest-risk path, explicit).
- Drain measurement: the multi-night procedure in docs/SUSPEND.md;
  median reported, not a single night.

### Firmware matrix

- `fwupdmgr get-devices`: detects the hardware (BIOS, EC, NVMe, TPM as
  applicable to this MTM).
- `fwupdmgr get-updates` (query only): succeeds; no update applied during
  the test.
- Rescue documented: for each updatable component, the recovery path if
  the update fails is written down before any update is attempted.
  Firmware is never flashed without a recorded before/after version pair.

## Rules for all hardware tests

- LOCAL label: every matrix above is labeled LOCAL in docs and comments.
  CI runs only `tests/`; it never claims hardware results.
- Evidence over assertion: "checked" means a command was run and its
  output recorded.
- Negative cases are mandatory where listed (PAM matrix, unsigned module
  rejection). A security control tested only in the positive direction is
  not tested.
- After any kernel, microcode, firmware, or UEFI change: re-run the Boot,
  KVM (check-iommu), and Power matrices at minimum. `cpu-security-report.sh`
  output is diffed against the 2026-09-21 baseline in docs/CPU_SECURITY.md.
