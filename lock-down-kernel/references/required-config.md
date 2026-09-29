# Required effective configuration

This is a review baseline, not a substitute for Kconfig dependency
resolution. Check the final generated `.config`, not only a fragment. A symbol
that Kconfig silently drops is a failure requiring investigation.

## Boot and userspace foundations

The effective configuration must preserve the dependencies needed by the
Ubuntu initramfs and userspace, including:

```text
CONFIG_64BIT=y
CONFIG_X86_64=y
CONFIG_SMP=y
CONFIG_PCI=y
CONFIG_ACPI=y
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TMPFS=y
CONFIG_CGROUPS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_UNIX=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_NETFILTER=y
CONFIG_NF_TABLES=y
CONFIG_NF_TABLES_INET=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_BLK_DEV_DM=y
CONFIG_DM_CRYPT=y
```

The root filesystem, initramfs compression, and any alternate filesystem must
be confirmed against the actual installation before changing them.

## Alder Lake power path

Keep and verify the dependency chain for:

```text
CONFIG_X86_INTEL_PSTATE=y
CONFIG_CPU_FREQ=y
CONFIG_INTEL_IDLE=y
CONFIG_NO_HZ_IDLE=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_MICROCODE=y
CONFIG_X86_THERMAL_VECTOR=y
CONFIG_INTEL_HFI_THERMAL=y
CONFIG_POWERCAP=y
CONFIG_INTEL_RAPL=y
```

`CONFIG_NO_HZ_FULL` is not a default laptop optimization. It requires a
specific workload and measurement. The kernel must not default to a periodic
tick or to a performance policy merely because the machine has HWP; validate
the interaction with the live `intel_pstate` policy and userspace power-policy
owner.

## Required platform functions

The target path normally needs:

```text
CONFIG_DRM=y
CONFIG_DRM_I915=y
CONFIG_DRM_DISPLAY_DP_HELPER=y
CONFIG_DRM_DISPLAY_HDMI_HELPER=y
CONFIG_BLK_DEV_NVME=y
CONFIG_NVME_CORE=y
CONFIG_TCG_TPM=y
CONFIG_TCG_TIS_CORE=y
CONFIG_TCG_TIS=y
CONFIG_THINKPAD_ACPI=y
CONFIG_USB=y
CONFIG_USB_XHCI_HCD=y
CONFIG_I2C_HID_ACPI=y
CONFIG_SERIO_I8042=y
CONFIG_MOUSE_PS2_ELANTECH=y
CONFIG_SND_HDA_INTEL=y
CONFIG_SND_HDA_CODEC_REALTEK=y
CONFIG_SND_HDA_CODEC_HDMI_INTEL=y
CONFIG_TYPEC=y
CONFIG_TYPEC_UCSI=y
CONFIG_UCSI_ACPI=y
CONFIG_TYPEC_DP_ALTMODE=y
CONFIG_SND_SOC_SOF_TOPLEVEL=y
CONFIG_SND_SOC_SOF_PCI=y
CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL=y
CONFIG_SND_SOC_SOF_HDA_COMMON=y
```

For networking, choose one deliberate module policy. A monolithic kernel
requires the MT7921U path to resolve to `=y`; a modular kernel requires
`CONFIG_MODULES=y`, a signed module workflow, and the matching initramfs:

```text
CONFIG_MT7921U=y   # monolithic policy
```

or:

```text
CONFIG_MODULES=y
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MT7921U=m
```

Do not claim module-signing enforcement when `CONFIG_MODULES` is disabled.

## Security and isolation baseline

The project threat model generally calls for:

```text
CONFIG_SECURITY=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_YAMA=y
CONFIG_SECURITY_LANDLOCK=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_DEFAULT_SECURITY_APPARMOR=y
CONFIG_INTEL_IOMMU=y
CONFIG_IRQ_REMAP=y
CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y
CONFIG_KVM_INTEL=y
```

Keep strong self-protection such as stack protection, fortification, hardened
usercopy, initialized allocations, slab freelist protections, KASLR, strict
kernel/module RWX, PTI, and architecture mitigations unless a concrete
compatibility failure is demonstrated. Record the exact symbol names for the
kernel version under review; do not copy names from another release.

## Deliberate decisions requiring evidence

Review rather than blindly forcing a value for:

- `CONFIG_BPF_SYSCALL`, BPF JIT, and unprivileged BPF policy;
- `CONFIG_USER_NS` and browser/container requirements;
- `CONFIG_IO_URING` and its userspace consumers;
- KVM, VFIO, and IOMMU default DMA mode;
- `CONFIG_MODULES` versus a truly monolithic kernel;
- crypto algorithms required by LUKS, networking, integrity, and userspace;
- `CONFIG_LSM` ordering and the runtime active LSM list.
