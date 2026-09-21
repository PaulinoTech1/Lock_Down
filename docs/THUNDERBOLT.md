# Thunderbolt posture: disabled

Purpose: eliminate pre-boot DMA exposure from the two Thunderbolt 4 / USB4 ports on a machine that uses no Thunderbolt peripherals.

Status: RECOMMENDED (disabled posture). Confidence: High on the exposure class; Medium on the exact firmware setting names until verified in this unit's UEFI.

## Why disabled

- No Thunderbolt dock, eGPU, or other Thunderbolt peripheral is used with this workstation. The ports carry only USB traffic (the Wi-Fi adapter is on a plain USB-A path).
- A Thunderbolt device gets DMA access to system memory unless the IOMMU contains it. Pre-boot (before the kernel's IOMMU policy is active), a malicious device plugged in at boot can read or write memory. Removing the exposure at the firmware level eliminates the class instead of mitigating it.
- DMA protection status on this unit is UNVERIFIED; the disabled posture does not depend on it.

## What disabled means here

1. UEFI: set the Thunderbolt pre-boot / OS control setting to its most restrictive option available (on Lenovo firmware this is typically a Thunderbolt enable/disable or a pre-boot authorization level). Verify the exact option name in this unit's UEFI setup and record it in the deployment notes. Target: Thunderbolt devices do not enumerate or get DMA before the OS.
2. Kernel: the `thunderbolt` driver stays EXCLUDED from the hardened kernel. Two NHI devices may still appear in sysfs/lspci listings; that is enumeration of the PCI functions, not an authorized device. Exclusion of the driver means no Thunderbolt device can be authorized or driven.
3. VT-d/IOMMU stays REQUIRED regardless. IOMMU is still needed for the xHCI USB ports and general DMA protection. Never present VT-d alone as making Thunderbolt safe; the posture here is belt and suspenders: firmware restriction plus no driver plus IOMMU.

## What to verify

- `dmesg | grep -i thunderbolt` shows the driver is absent (module not loaded).
- The NHI PCI functions, if visible, have no driver bound.
- `dmesg | grep -i "DMAR"` / IOMMU active (see scripts/check-iommu.sh conventions from the inventory work).
- UEFI setting recorded: exact menu path and chosen value.

## If a Thunderbolt dock is ever needed

Re-enable deliberately, in this order:

1. Decide the authorization policy first (user authorization via boltctl, or pre-boot levels in UEFI). Default to the strictest that still works with the dock.
2. Verify IOMMU/VT-d is active and DMA protection is reported before the first untrusted device is attached.
3. Reintroduce the `thunderbolt` driver, test the dock, and update this document with the new posture. The disabled posture documented here is then superseded, explicitly, in writing.

## Limitation

- Firmware settings are only as trustworthy as the firmware; a compromised UEFI could lie about them. This control assumes the firmware is intact (measured boot / Boot Guard context, see the inventory report).
- USB4 tunneling over the same ports shares some exposure surface; with the driver excluded and the ports restricted in firmware, the practical surface is USB-only.
- Disabling in firmware does not remove the PCI devices from enumeration; do not mistake "still visible in lspci" for "still active."

## Recovery

- If the firmware setting breaks USB-C display or USB data on those ports (unexpected, but verify), re-enter UEFI setup and restore the previous value. Record the previous value before changing it.
- The rescue kernel is unaffected by this policy; it is a firmware plus driver decision, not a boot-path decision.

## Cost

Loss of future Thunderbolt peripheral use until deliberately re-enabled. On a machine with no TB peripherals, that cost is zero.
