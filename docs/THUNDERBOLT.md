# Thunderbolt, USB-C, and external monitor policy

Updated 2026-09-25 for the ThinkPad T14 Gen 3 Intel (21AJ).

## Observed state

- The running Ubuntu 7.0.0-31-generic kernel has the `thunderbolt` driver
  bound to both Thunderbolt 4 NHI functions, PCI 00:0d.2 and 00:0d.3.
- On running `6.18.53-lockdown-t14g3-audit3`, both NHI functions still appear
  in `lspci -nnk`, but neither has a kernel driver bound. `boltctl list` and
  `boltctl domains` return no entries. The xHCI USB function at 00:0d.0 remains
  bound to `xhci_hcd` for ordinary USB use. PCI function enumeration by itself
  does not establish that a PCIe tunnel is active or authorized.
- UCSI ACPI exposes two Type-C ports. i915 exposes HDMI-A-1, DP-1 through
  DP-4, and the internal eDP connector.
- No external monitor was connected during the original check. Firmware exposes
  a `ThunderboltAccess` setting through ThinkLMI, but its `current_value` is
  root-readable only and was not obtained in this audit. A separate PCIe
  tunneling setting was not exposed in the unprivileged firmware-setting list.
  Inspect UEFI setup for one; the previous claim that Thunderbolt was disabled
  in firmware remains unverified.

## Supported display paths in the custom profile

The owner needs an external monitor and does not need Thunderbolt peripherals.
The custom Linux 6.18.53 profile keeps i915, Type-C/UCSI ACPI, DisplayPort
Alternate Mode, and HDMI/DisplayPort audio built in. It excludes `CONFIG_USB4`
and `CONFIG_TYPEC_TBT_ALTMODE`, the relevant options in this kernel tree.

Direct HDMI and direct USB-C to DisplayPort/HDMI adapters are the intended
paths. A USB-C monitor using native DisplayPort Alternate Mode is also within
scope. A Thunderbolt/USB4 dock that requires tunneled DisplayPort, PCIe, or
USB4 networking is not supported by this profile. A USB-C dock that uses
ordinary USB and DisplayPort Alternate Mode may work, but needs a real test.
The connector shape alone cannot tell which dock implementation is used.

## Security boundary

Omitting the USB4 driver prevents the custom kernel from driving tunneled
devices through those NHI functions. It does not prove that firmware blocked
pre-boot DMA, and it does not substitute for VT-d/IOMMU and interrupt
remapping. Keep the firmware authorization setting restrictive if one is
available, and record its exact value after inspection in UEFI setup.

## Validation before daily use

1. Boot the candidate explicitly while retaining the Ubuntu rescue kernel.
2. Connect the actual monitor through HDMI; verify a stable image, modes,
   audio if needed, and reconnect after s2idle resume.
3. Repeat through the actual direct USB-C adapter or USB-C monitor used daily.
   Check `cat /sys/class/drm/card*-*/status` and the desktop display settings.
4. Confirm `/sys/class/typec/port*` exists, and confirm the NHI functions
   have no `thunderbolt` driver bound on the custom kernel.
5. Read `ThunderboltAccess` with
   `sudo cat /sys/class/firmware-attributes/thinklmi/attributes/ThunderboltAccess/current_value`;
   inspect UEFI setup for a separate PCIe-tunneling control and record its
   exact displayed value without changing it during this audit.
6. If a required display path only works through a Thunderbolt/USB4 dock,
   revise the profile deliberately, enable `CONFIG_USB4`, and test the dock
   under the intended authorization and IOMMU policy.

## Recovery

If the candidate fails to drive the monitor, select the retained Ubuntu
kernel from GRUB. Recheck the adapter/dock type and the resolved `.config`
before changing firmware settings or rebuilding.
