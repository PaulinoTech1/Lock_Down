# Intel Display Power

GPU: Intel Iris Xe ADL-P GT2 (8086:46a8), i915 driver only.
Panel: BOE NV140WUM-N43, 1920x1200, 60 Hz, eDP.
Firmware stack in use: DMC 2.20, GuC 70.49.4, HuC 7.9.3 (VERIFIED from inventory).

## Policy: evaluate, do not force

i915 power features are measured before they are enabled. The default is
whatever the distro kernel negotiates; this document records what to check
and what the known observations are. Nothing here is a forced default.

## Feature inventory

### GuC / HuC / DMC firmware

- Purpose: GuC (graphics microcontroller) enables submission and power
  management offload; HuC enables media workload features; DMC (display
  microcontroller) handles display power sequencing including DC states.
- Observed: the running stack already loads DMC 2.20, GuC 70.49.4, HuC
  7.9.3 (VERIFIED from inventory). The kernel parameters
  `i915.enable_guc=3` semantics are distro-default on current Ubuntu; do
  not override without a measured reason.
- Cost of forcing: a wrong GuC mode can break display resume. The observed
  working set is the baseline; record it before changing anything.
- Limitation: firmware versions are blobs; newer is not automatically
  better on this panel. Pin to the observed set unless a newer set is
  verified stable on this exact panel.
- Recovery path: `i915.enable_guc=0` on the kernel command line reverts to
  no-GuC operation for diagnosis.

### FBC (Frame Buffer Compression)

- Purpose: compresses the framebuffer in memory, saving memory bandwidth
  and power on mostly-static screen content.
- OBSERVED (VERIFIED from inventory): current scanout is XR30 (30-bit),
  which currently blocks FBC. FBC is not active, and this is a stack/pixel-
  format limitation, not a panel defect.
- EXPERIMENTAL test (24-bit scanout): whether the KDE/Wayland compositor
  can run at a 24-bit scanout to unblock FBC is UNVERIFIED and is an
  experiment, not a default.
  - How to try: in the KDE display settings or compositor config, select a
    24-bit color depth / disable 30-bit (deep color) output for the eDP
    panel, then check `i915` FBC status (see the script).
  - How to measure: compare `check-intel-display.sh` FBC status before and
    after; measure package power (e.g., `turbostat` or battery discharge
    rate at idle with a static screen) over at least 30 minutes per state.
  - How to revert: re-enable 30-bit scanout; FBC returns to blocked state.
    No persistent change is made by the test itself.
  - Never present as a safe default: 30-bit scanout exists for color
    depth; dropping to 24-bit is a visible quality tradeoff, and FBC power
    savings on a 14-inch laptop panel workload may be unmeasurable. The
    experiment decides; do not assume the outcome.
- Cost of FBC when active: negligible; occasional compression artifacts
  are theoretically possible but not observed as a practical issue.
- Limitation: FBC saves power only when the screen is static-ish; video
  playback and animation bypass most of the benefit.

### PSR (Panel Self Refresh)

- Observed: PSR unavailable in the current graphics stack (VERIFIED from
  inventory as a stack limitation). Whether the panel itself supports PSR
  is UNVERIFIED.
- Policy: do not force PSR on (`i915.enable_psr=1`) to chase a feature the
  stack reports unavailable. If a future kernel stack reports PSR support,
  evaluate then: measure idle power with PSR on vs off, watch for
  flicker/artifacts over a full workday, and only then consider enabling.
- Cost of forcing an unsupported PSR: display flicker, failed resume, or
  silent fallback. Not worth it.
- Limitation: even working PSR only helps on static content.

### Runtime PM (runtime power management)

- Purpose: lets the GPU drop to low-power states when idle.
- Policy: keep the distro default (runtime PM on for i915). Verify with
  the script (`/sys/bus/pci/devices/0000:00:02.0/power/control` should read
  `auto`).
- Cost: none observed. Limitation: aggressive autosuspend delays on the
  GPU can add resume latency to the first frame after idle; the default
  delay is tuned for this.

## What the read-only script reports

`scripts/check-intel-display.sh`:

- i915 module parameters in effect (GuC/HuC enablement, FBC, PSR).
- FBC status, PSR status where exposed in sysfs/debugfs.
- Runtime PM control state for the GPU PCI device.
- DMC/GuC/HuC firmware load status where readable.
- Panel info (resolution, refresh) where readable.
- Read-only: it never writes module parameters or sysfs values.

## Confidence notes

- XR30 scanout blocking FBC, PSR unavailable in current stack, firmware
  versions: VERIFIED from inventory. Confidence: High.
- 24-bit-scanout FBC experiment outcome: UNVERIFIED. Confidence: Low until
  measured on the machine.
- Panel-side PSR support: UNVERIFIED. Confidence: Low.
