# KDE Plasma on this workstation

Target: Ubuntu LTS base, KDE Plasma on Wayland only. No Xorg session.

## Install scope: required components only

Minimal `plasma-desktop` metapackage plus the pieces below. Purpose: a
small, auditable desktop with fewer background services, fewer network
listeners, and fewer update surfaces. Each component earns its place.

Required:

- `plasma-desktop` (minimal): Plasma shell, panels, basic applets.
- KWin Wayland (`kwin-wayland`): the Wayland compositor. This is the only
  session type installed.
- SDDM (`sddm`): display manager. Configure for Wayland sessions.
- NetworkManager (`network-manager`, `plasma-nm`): network control. The
  only network path is the external USB Wi-Fi adapter; NetworkManager owns
  it.
- PipeWire (`pipewire`, `pipewire-pulse`, `wireplumber`): audio. Replaces
  PulseAudio; required by the HDA/SOF audio path and by screen sharing
  portals.
- Power management: exactly ONE policy owner (see below).
- Notifications (`plasma-workspace` covers it): security update and
  firewall prompts must reach the user.
- Terminal (`konsole`): administrative work.
- File manager (`dolphin`): minimal file operations.
- fwupd frontend (`plasma-discover` backend or `fwupdmgr` CLI): firmware
  updates are reviewed, never automatic. The GUI is optional; the CLI is
  required.
- System Settings (`systemsettings`): display, power, and input
  configuration.

XWayland (`xwayland`): installed for application compatibility
(applications that have no native Wayland backend), but no Xorg session
is installed or offered at login. Purpose: run the long tail of X-only
apps without maintaining a full X session. Cost: XWayland clients do not
get Wayland's isolation properties (any X client can snoop other X
clients); treat XWayland apps as less isolated than native Wayland apps.
Limitation: this is app-compat pragmatism, not a security boundary.

## What to avoid

- PIM bundles (KMail, KOrganizer, Akonadi and its MySQL backend): large,
  networked, historically bug-prone; the user does not need them on a
  hardened workstation. If mail/calendar is needed, use the web or a
  single-purpose client, not the full PIM stack.
- Games (`kdegames` and friends): no place on this image.
- Extra file-indexing beyond Baloo's default: Baloo stays but with
  conservative scope (home directory only, no removable media indexing).
  Full-content indexing of everything is a metadata leak if the index is
  ever exfiltrated; keep it minimal.
- KDE Connect: tempting, but it opens network listeners and a phone
  pairing surface. OPTIONAL only if the user explicitly wants it, with the
  firewall default-deny and pairing done deliberately. Default: not
  installed.
- Anything that installs its own power policy daemon (see below).

## One power-policy owner only

Choice: KDE PowerDevil. (RECOMMENDED)

- Rationale: PowerDevil is integrated with the Plasma session the user
  actually runs. It handles lid-close, idle-dim/suspend, and per-power-
  source profiles inside the desktop session, and it reads the same
  `power/` profile files this repo ships (see `../power/`).
- Therefore `power-profiles-daemon` (PPD) must NOT be installed or must be
  masked. Two policy owners fight: PPD and PowerDevil both write EPP and
  platform-profile values, and the result is flapping settings and
  unpredictable behavior under load.
- If the machine ever runs headless or under a different session, revisit:
  PPD would then be the owner and PowerDevil the one removed. Exactly one
  at a time, documented at change time.
- The repo's power profiles (`power/battery.conf`, `power/balanced.conf`,
  `power/ac-performance.conf`) are consumed by PowerDevil. They respect the
  existing 75/80% charge thresholds and never change them.
- Cost of this choice: PowerDevil only manages power inside a Plasma
  session; console/TTY sessions get kernel defaults. Acceptable: the
  workstation is used via Plasma.
- Limitation: PowerDevil is not a security boundary; it is a policy
  applier. The hardening value is consistency (one owner, no fights), not
  protection.
- Recovery path: if power behavior goes wrong, stop PowerDevil
  (`systemctl --user stop plasma-powerdevil`) and confirm the kernel
  defaults are sane before re-enabling. The thresholds live in sysfs /
  thinkpad_acpi, not in PowerDevil, so a PowerDevil failure cannot brick
  charging policy.

## Session hardening notes

- Wayland session only at SDDM: remove or never install
  `plasma-workspace-x11`. An offered-but-unused Xorg session is an
  unmaintained attack surface.
- Screen lock: engage on suspend and on idle (10 minutes idle is the
  default; tighten per user preference). The lock must engage even if the
  compositor is under load; test it.
- SDDM runs as its own user; keep it patched with the rest of the system.
- No auto-login. Ever.

## Confidence notes

- Component list: RECOMMENDED for the stated goals. Confidence: High that
  minimal-scope reduces surface; Medium on the exact Ubuntu package names
  (verify with `apt-cache` at install time; names drift between releases).
- PowerDevil-over-PPD choice: RECOMMENDED with the stated rationale.
  Confidence: High that exactly-one-owner is correct; Medium that
  PowerDevil remains the better owner if the session mix changes.
