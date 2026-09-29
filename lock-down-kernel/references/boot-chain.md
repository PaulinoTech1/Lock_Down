# Boot, signing, and recovery chain

The intended production chain is:

```text
UEFI firmware trust database
  -> Ubuntu shim / GRUB
  -> signed kernel image
  -> kernel lockdown under Secure Boot
  -> initramfs and root unlock
  -> signed in-tree or DKMS modules, if modules are enabled
```

## Before installation

- Confirm the exact kernel release and configuration hash.
- Keep the Ubuntu distro kernel installed and bootable.
- Verify the initramfs contains the storage, filesystem, DM-crypt, TPM, and
  firmware pieces required by the actual root path.
- If modules are enabled, verify every required module is signed by a key
  trusted by the running kernel. `CONFIG_MODULE_SIG_FORCE=y` is meaningless if
  module support is disabled or the signing key is unavailable.
- Never put a private signing key in the repository. The repository may contain
  only public certificates or paths to external keys.

## Secure Boot validation

Use read-only checks such as:

```bash
mokutil --sb-state
cat /sys/kernel/security/lockdown
cat /proc/sys/kernel/modules_disabled
dmesg | grep -iE 'secure.?boot|lockdown|module signature|integrity'
scripts/verify-secure-boot.sh
```

The classic signed-vmlinuz path does not automatically authenticate a separate
initramfs or bootloader command line. Treat a UKI as a separate artifact
pipeline, not as a free hardening toggle.

## Recovery invariant

Do not remove older working kernels. If the custom kernel fails, select the
Ubuntu kernel from GRUB, repair the installed image/initramfs from the running
system or a live-media chroot, and only retry after identifying the failure.
Secure Boot/MOK recovery must be documented before enrollment; do not disable
security controls as an unrecorded troubleshooting step.
