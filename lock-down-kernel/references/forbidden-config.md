# Production exclusions and rejected shortcuts

These are defaults for the hardened profile on the supported ThinkPad, not a
license to remove dependencies without checking the effective configuration.

## Production exclusions

The following should remain disabled unless the user explicitly changes the
hardware or threat model and validates the result:

```text
# CONFIG_HZ_PERIODIC is not set
# CONFIG_NO_HZ_FULL is not set
# CONFIG_ACPI_DEBUG is not set
# CONFIG_DEBUG_FS is not set
# CONFIG_DYNAMIC_DEBUG is not set
# CONFIG_KGDB is not set
# CONFIG_STACK_TRACER is not set
# CONFIG_KASAN is not set
# CONFIG_KCSAN is not set
# CONFIG_KPROBES is not set
# CONFIG_FUNCTION_TRACER is not set
# CONFIG_USB4 is not set
# CONFIG_BT is not set
# CONFIG_DRM_AMDGPU is not set
# CONFIG_DRM_RADEON is not set
# CONFIG_DRM_NOUVEAU is not set
# CONFIG_IWLWIFI is not set
# CONFIG_USB_VIDEO_CLASS is not set
```

Diagnostic builds may re-enable tracing or probing for a specific investigation,
but must remain clearly labeled, signed, recoverable, and never silently become
the production default.

For the 6.18.53 profile, `CONFIG_EXPERT=y` selects `CONFIG_DEBUG_KERNEL=y`.
Keeping EXPERT retains the Ubuntu base's 32/16-bit mmap ASLR defaults;
disabling it silently reduces them to 28/8. Treat DEBUG_KERNEL as an umbrella
in this case, not a standalone debug interface. The resolved production config
must instead disable the actual debugger, debugfs, dynamic debug, and function
and stack tracers, and gate the two ASLR values explicitly.

## Security shortcuts that are not acceptable defaults

- Do not add `mitigations=off`, `spectre_v2=off`, `mds=off`, or equivalent
  command-line shortcuts for benchmark results.
- Do not disable IOMMU, interrupt remapping, lockdown, AppArmor, or module
  signature enforcement merely to make a device or VM start.
- Do not enable every LSM or list unavailable LSMs in `CONFIG_LSM` and call the
  result defense-in-depth. The compiled providers, ordering, and runtime state
  must agree.
- Do not enable `CONFIG_ACPI_DEBUG`, dynamic tracing, or debugfs in a shipped
  profile simply because they make troubleshooting easier.
- Do not remove TPM, EFI, firmware-loader, storage, suspend, USB, audio, or
  rescue support based only on one idle collection window.

## Cargo-cult optimizations to flag

Call out recommendations that only reduce image size or compile time without a
credible runtime mechanism, including removing never-executed built-in drivers,
arbitrary HZ changes, forcing a governor under HWP, disabling high-value
mitigations, or copying random sysctl/powertop changes into Kconfig.
