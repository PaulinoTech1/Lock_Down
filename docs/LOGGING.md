# Logging

Purpose: keep enough local security-relevant log data to answer "what happened" after an incident, without building a SIEM the workstation does not need.

Status: RECOMMENDED (light logging only). Confidence: High.

## What is logged

- journald: the default system log on Ubuntu. Service logs, kernel messages, and authentication events land here. Keep the default; do not disable journald.
- auditd: OPTIONAL, kept light if used. Justification for recommending it: auditd gives syscall-level records (file access, privilege use) that journald does not. Recommendation: install auditd with a minimal ruleset (logins, sudo use, module loads, time changes) only if incident investigation matters more than the extra log volume. For a single-user workstation, journald plus the kernel logs below is the default; auditd is the upgrade path.
- Kernel security logs: lockdown, module signature rejections, IOMMU faults, AppArmor denials. These are the early warning for tampering or misconfiguration.
- AppArmor denials: review after every profile change and after package upgrades.
- Auth logs: sudo use, login failures, screen unlock events. Watch for unexpected failures.
- Firmware and kernel update records: before/after versions for every firmware flash and kernel change (see the inventory report's firmware section). These are written by hand at update time.

## What to watch

- Repeated auth failures on sudo, login, or SDDM (possible guessing or a misconfigured PAM change).
- AppArmor denials on profiles you did not just change (possible compromise or upgrade drift).
- Module signature rejections after Secure Boot enablement (possible tampering or an unsigned module you forgot).
- IOMMU/DMA faults (possible misbehaving device or driver).
- Unexpected USB device authorizations (check against the USBGuard policy).

## Retention

- Keep journald's default retention unless disk space forces a change. If space is tight, cap with `SystemMaxUse` in journald.conf rather than disabling logging.
- Update records (firmware/kernel versions) are kept indefinitely in the project notes; they are small and invaluable.
- Rotate and compress normally; do not ship logs off the machine by default.

## How to query

```text
journalctl -b -p err                      # errors this boot
journalctl -t sudo --since "1 day ago"    # sudo use in the last day
journalctl -t audit --since "1 day ago"   # auditd records (if installed)
journalctl -k -g -i "apparmor.*DENIED"    # AppArmor denials (kernel log)
journalctl -k | grep -i "Lockdown:"       # lockdown events
lastb                                     # failed login attempts
```

## Privacy

Logs stay local. No forwarding to a SIEM, no cloud log service, no telemetry. If a log line contains something sensitive (a username in an auth failure is normal; anything more is not), redact before sharing the log with anyone.

## Limitation

- Local logs are trustworthy only while the system is. A successful root compromise can alter them; this is why the update records and the offline second YubiKey (see docs/YUBIKEY_PAM.md) matter for recovery, not log integrity.
- Light logging means some questions will be unanswerable after the fact. That is the accepted tradeoff; auditd is the lever if the tradeoff changes.

## Cost

Disk space (small) and the habit of looking. The queries above take seconds.
