# Hardware inventory and decision boundary

This skill is for the one supported machine documented by the repository. The
following is the design baseline recorded in `docs/HARDWARE.md`; re-check
load-bearing facts on the live machine before removing or adding drivers.

## Verified baseline

- Lenovo ThinkPad T14 Gen 3 Intel, machine type 21AJ, Core i5-1245U Alder
  Lake-U, 2 performance cores plus 8 efficiency cores, 12 threads.
- Intel `intel_pstate`, HWP/HFI, Intel idle states, and package C10 are
  expected and must be confirmed in runtime telemetry.
- Intel Iris Xe integrated graphics using i915; no discrete GPU.
- Samsung PM9A1 NVMe; APST is expected to remain enabled.
- Nuvoton TPM 2.0 using TCG TIS.
- UEFI system with Secure Boot planned as the production trust anchor.
- Internal AX211 Wi-Fi was removed. The only intended network path is the
  external MediaTek MT7921U USB adapter, VID:PID `0e8d:7961`, on the documented
  USB port. Confirm this before enforcing USB authorization.
- No PCI Ethernet NIC, Bluetooth use, webcam, fingerprint reader, or
  Thunderbolt peripheral is intended. The running Ubuntu kernel bound both
  Thunderbolt NHI controllers on 2026-09-23, so firmware disablement remains
  unverified. External HDMI and direct USB-C DisplayPort monitors are required.
- Audio uses the Intel SOF/HDA path with a Realtek codec. Do not remove audio
  merely because the codec is not a separate PCI device.
- Suspend target is s2idle only according to the project runtime log; never
  infer S3 support from generic kernel documentation.
- KVM/Intel virtualization and VT-d/IOMMU are intentional for untrusted VM
  profiles. Capability is not the same as active enforcement; verify both.

## Required evidence before hardware-specific pruning

Collect or inspect, where available:

```bash
lspci -nnk
lsusb -nn
lsmod
cat /proc/cmdline
cat /sys/power/mem_sleep
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_driver
cat /sys/devices/system/cpu/intel_pstate/status
cat /sys/kernel/iommu_groups/*/devices/* 2>/dev/null
dmesg | grep -iE 'ACPI|DMAR|IOMMU|i915|nvme|SOF|HDA|mt7921|TPM|suspend'
```

The absence of a raw inventory in the repository is an evidence gap. Treat
documentation summaries as intent until the live machine or archived command
output confirms them.

## Do not confuse boundaries

- Secure Boot and UEFI protect the boot trust chain; they do not replace LUKS.
- LUKS protects data at rest; TPM sealing affects unlock policy and recovery,
  not kernel runtime integrity by itself.
- IOMMU protects DMA mappings after it is initialized; firmware pre-boot DMA
  policy and Thunderbolt authorization remain firmware responsibilities.
- AppArmor and userspace sandboxing are not replaced by removing unrelated
  kernel drivers.
