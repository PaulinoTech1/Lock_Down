.TH LOCK-DOWN-KERNEL-AUDIT 1 "29 September 2026" "Lock_Down" "Kernel Audit Change Log"
.SH NAME
Lock_Down custom kernel audit and change log
.SH SUMMARY
This document records the read-only audit, hardware evidence, configuration findings, repository changes, and validation performed for the Lenovo ThinkPad T14 Gen 3 Intel custom Linux 6.18.53 kernel.
.PP
The earlier signed audit2 kernel booted but failed functional validation. Audit3 was signed, installed, and booted with essential paths working; its runtime and physical checklist is still incomplete. Audit4 is signed but not installed. Audit5 carries the non-Lenovo driver and unused-radio removals; its resolved config passed static gates, but the package build did not complete. Audit6, audit7, audit8, and audit9 were separately built, signed, installed, and booted. Audit9 is currently running with owner-reported physical hardware checks passing; the owner has not yet completed KVM/VM testing, suspend, or fallback testing. Audit10 removes 28 specialty/test/legacy-bridge USB options from audit9; it is built and MOK-signed but not installed or booted. The stock Ubuntu kernel remains installed with GRUB_DEFAULT=0.
.SH TARGET PLATFORM
.IP \(bu 2
Lenovo ThinkPad T14 Gen 3 Intel, machine type 21AJ.
.IP \(bu 2
Intel Core i5-1245U Alder Lake-U: 10 cores, 12 threads, P- and E-core topology.
.IP \(bu 2
Intel Iris Xe graphics using i915; Samsung PM9A1 NVMe; Nuvoton TPM 2.0.
.IP \(bu 2
External MediaTek MT7921U USB Wi-Fi adapter, USB ID 0e8d:7961.
.IP \(bu 2
UEFI Secure Boot enabled; running host reported lockdown integrity mode.
.IP \(bu 2
Suspend interface exposed s2idle only.
.SH INITIAL AUDIT FINDINGS
.SS Effective configuration
The existing linux-6.18.53/.config did not match the documented hardened fragment. The project audit found the following significant defects:
.IP \(bu 2
NO_HZ_IDLE and HIGH_RES_TIMERS were disabled, while periodic HZ was enabled.
.IP \(bu 2
The performance governor was selected by default, contrary to the intended HWP-aware laptop policy.
.IP \(bu 2
The effective configuration lacked Intel IOMMU and IRQ remapping; KVM Intel support was also absent.
.IP \(bu 2
Audio, SOF/HDA dependencies, and MT7921U Wi-Fi were absent.
.IP \(bu 2
ACPI debug support was enabled despite the production exclusion policy.
.IP \(bu 2
The fragment referenced CONFIG_MICROCODE_INTEL, which is not a valid separate symbol in this Linux 6.18.53 tree; the applicable symbol is CONFIG_MICROCODE.
.IP \(bu 2
The existing configuration was monolithic with CONFIG_MODULES disabled, making its module-signing claims internally inconsistent.
.SS Live hardware evidence
The live audit confirmed the CPU, i915 graphics, NVMe controller, TPM, audio device, USB Wi-Fi adapter, and s2idle assumptions. It also found an important contradiction:
.PP
Thunderbolt 4 controllers were enumerated and the Thunderbolt driver was active. Project documentation had treated Thunderbolt as disabled in firmware; that claim is unverified. The follow-up below records the revised custom-kernel policy for external monitors.
.SH CHANGES IMPLEMENTED
.SS config/hardened.config
.IP \(bu 2
Corrected the usage path from repo/config/hardened.config to config/hardened.config.
.IP \(bu 2
Added NO_HZ_IDLE and HIGH_RES_TIMERS; explicitly disabled NO_HZ_FULL.
.IP \(bu 2
Selected schedutil as the intended default CPUFreq policy and explicitly disabled performance and powersave defaults.
.IP \(bu 2
Replaced the invalid microcode symbol with CONFIG_MICROCODE=y.
.IP \(bu 2
Disabled CONFIG_ACPI_DEBUG for the production profile.
.IP \(bu 2
Added the required sound, ALSA, HDA, SOF, and Intel SOF dependency symbols using names supported by Linux 6.18.53.
.IP \(bu 2
Changed MT7921U from a module request to built-in support, consistent with the monolithic profile.
.IP \(bu 2
Added PCI MSI, NETDEVICES, CFG80211, and MAC80211 prerequisites for the target USB Wi-Fi path.
.IP \(bu 2
Enabled KVM, KVM Intel, Intel IOMMU, IRQ remapping, and Intel IOMMU default-on policy.
.IP \(bu 2
Made the module policy explicit: CONFIG_MODULES is disabled, so there are no loadable modules to sign or load after boot.
.IP \(bu 2
Added NETFILTER and NETFILTER_ADVANCED prerequisites for nftables.
.SS scripts/build-kernel.sh
.IP \(bu 2
Fixed repository-root calculation and removed the invalid repo/ path prefix.
.IP \(bu 2
Aligned the documented point release with the checked-out Linux 6.18.53 tree.
.IP \(bu 2
Replaced merge_config.sh-only application with fragment append followed by Kconfig olddefconfig, because sparse base configurations can omit symbols that must be introduced by the fragment.
.IP \(bu 2
Stopped copying private signing keys into the source tree. Modular signing paths are now external and overridable with SIGN_KEY_PATH and SIGN_CERT_PATH.
.IP \(bu 2
Made dry-run signing checks avoid reading a nonexistent generated .config.
.SS Audit and preflight tooling
.IP \(bu 2
Updated lock-down-kernel/scripts/audit-config.sh to check CONFIG_MICROCODE and the Linux 6.18.53 SOF symbol names.
.IP \(bu 2
Updated lock-down-kernel/references/required-config.md with the corrected microcode and audio symbols.
.IP \(bu 2
Restored executable permissions on the top-level preflight-check.sh wrapper.
.SH VALIDATION
.SS Candidate fragment validation
A temporary configuration was created outside the repository by appending config/hardened.config to the existing source configuration and running make olddefconfig.
.IP \(bu 2
Required configuration audit: 0 required failures.
.IP \(bu 2
Boot-critical validation: 48 passes, 0 failures, 1 warning.
.IP \(bu 2
Warning: CONFIG_CHECKPOINT_RESTORE was disabled; it is not required for the documented boot path.
.IP \(bu 2
Resolved target symbols included NO_HZ_IDLE=y, HIGH_RES_TIMERS=y, CONFIG_MICROCODE=y, CONFIG_INTEL_IOMMU=y, CONFIG_IRQ_REMAP=y, CONFIG_KVM_INTEL=y, CONFIG_MT7921U=y, and the corrected SOF symbols.
.SS Existing tree validation
The checked-in built .config was not overwritten. It still represents the pre-change candidate and therefore still fails the power/IOMMU portions of the audit. The existing vmlinux identifies as Linux 6.18.53 and was built before these changes.
.SS Script validation
.IP \(bu 2
Shell syntax checks passed for the modified scripts.
.IP \(bu 2
git diff --check passed.
.IP \(bu 2
build-kernel.sh --dry-run completed without path or signing-policy errors.
.SH FOLLOW-UP: EXTERNAL MONITORS AND CANDIDATE BUILD
.PP
On 23 September 2026 the owner specified that Thunderbolt peripherals are not required, but an external monitor is required. The running Ubuntu kernel exposed HDMI-A-1 and DP-1 through DP-4 through i915; all external connectors were disconnected during inspection. UCSI ACPI exposed two Type-C ports. Both Thunderbolt NHI functions were bound to the thunderbolt driver on the running Ubuntu kernel. The firmware authorization state remains unverified.
.PP
The hardened fragment now keeps i915, DisplayPort and HDMI helpers, Type-C/UCSI ACPI, DisplayPort Alternate Mode, and Intel HDMI/DisplayPort audio. It excludes the actual Linux 6.18.53 USB4/Thunderbolt option, CONFIG_USB4, and the Thunderbolt alternate-mode driver. Direct HDMI and USB-C DisplayPort adapters are the intended external-monitor paths. A Thunderbolt dock requiring USB4 tunneling is outside this profile. No physical monitor was connected for an end-to-end test.
.PP
The follow-up config audit also found and corrected missing SMP and INET prerequisites. Their absence had hidden schedutil and nftables even though the fragment requested them. The fragment now includes IPv4, IPv6, required nftables expressions, Intel RAPL, the Linux 6.18 page-table isolation symbol, and built-in optional USB Ethernet dependencies. Module-signing assignments that cannot apply to the monolithic profile were removed. A unique local version avoids a release-name collision with the installed 6.18.53 kernel.
.SS Resolved configuration
.IP \(bu 2
Final release: 6.18.53-lockdown-t14g3-audit1.
.IP \(bu 2
Required config audit: zero failures. Preflight: 71 passes, zero failures, one warning for disabled CHECKPOINT_RESTORE.
.IP \(bu 2
make olddefconfig: zero warnings; make listnewconfig: no new symbols.
.IP \(bu 2
merge_config.sh reported 16 deliberate overrides of prior base values. The remaining five fragment-to-config differences were requests to disable symbols already absent because their parent menus were disabled. No requested enabled symbol was silently dropped.
.SS Build result
.IP \(bu 2
make -j12 bzImage completed successfully. The first and final compiler logs contained zero warnings and zero errors.
.IP \(bu 2
Final resolved config SHA-256: ff79426e4efbc02a8836bc97d063ac78da1ce9825bb8df2f9bb0dad975293af5.
.IP \(bu 2
Final bzImage SHA-256: 4f8065059053245dbcec5fddce456a9c21bbbc2f955b4259df5d0b6f7ab97322.
.IP \(bu 2
The full resolved config was copied to config/candidate-6.18.53-lockdown-t14g3-audit1.config.
.IP \(bu 2
Debian package creation stopped before packaging: debhelper-compat (= 12) and libdw-dev were not installed. Two maintainer-email-format warnings were harmless; the missing build dependencies were blocking. The build script now checks package dependencies early. No .deb was produced.
.SH FOLLOW-UP: BOOT AND MEASUREMENT READINESS
.PP
On 23 September 2026, a read-only follow-up checked the currently booted Ubuntu kernel, existing boot artifacts, the enrolled MOK, and the candidate build. This section records checks and owner-provided recovery information; it does not imply installation or a successful candidate boot.
.SS Current boot and fallback evidence
.IP \(bu 2
The machine still runs Ubuntu 7.0.0-31-generic. mokutil reports Secure Boot enabled and the running kernel reports integrity lockdown. The running kernel is not the candidate.
.IP \(bu 2
The owner inspected GRUB and reported entries for Ubuntu 7.0.0-31-generic, Ubuntu 7.0.0-29-generic, and the older 6.18.53 image. Entries and files exist, but fallback boot was not exercised. GRUB_DEFAULT=0, GRUB_TIMEOUT_STYLE=hidden, and GRUB_TIMEOUT=0; a visible rescue menu must be arranged before the first candidate boot.
.IP \(bu 2
The owner inspected the older /boot/initrd.img-6.18.53 and found cryptsetup and LVM userspace. That initramfs belongs to the older kernel, not the audit1 candidate. Its existence does not prove that the audit1 candidate can unlock LUKS or mount the root filesystem.
.IP \(bu 2
The existing /boot/vmlinuz-6.18.53 has SHA-256 52b41e9fc1bc3345d2a2939543a044a4bf3647b11f7528e209f8dde526a9f087 and differs from the audit1 bzImage. The audit1 bzImage has no Secure Boot PE signature. No audit1 package, installed image, or initramfs exists yet.
.SS MOK and recovery readiness
.IP \(bu 2
The enrolled public certificate has subject CN=Paulino Power MOK and SHA-1 fingerprint 3A:B0:D3:62:4F:65:F4:0B:4B:C7:06:3A:4E:E3:28:E5:B8:E5:BE:F6. It was exported to a temporary location; its PEM form passed sbverify against the older signed 6.18.53 image. A matching PEM public certificate was also found outside the repository.
.IP \(bu 2
The owner locally derived a SHA-256 digest of the public key in the private MOK file, f61f36bcbe6fefac87b5b126fd685a1f78fe5aa2cef7afee45e1766b60462ca4. It matches the digest derived from the enrolled certificate. The private key and passphrase were not copied into this report or repository.
.IP \(bu 2
The owner reports a bootable stock Ubuntu recovery USB and possession of the LUKS passphrase, but no disk backup. The owner reports no critical data on this laptop. These facts reduce data-loss impact but do not prove the rescue workflow or eliminate downtime/reinstallation risk.
.SS Limited stock-kernel power baseline
.IP \(bu 2
Three five-second unprivileged turbostat summary samples were collected on the stock 7.0.0-31-generic kernel. Reported C10 percentages were 89.29, 88.68, and 89.05; reported IRQ counts were 12482, 13923, and 13038 per sample. These are not a controlled stock-versus-candidate comparison.
.IP \(bu 2
Access to MSR and perf counters was restricted, so package watts, complete wakeup rates, and defensible package C-state comparisons were not captured. No CPU workload or suspend/resume test was run. The candidate has not been booted.
.SS Newly identified pre-install checks
.IP \(bu 2
The audit1 candidate had CONFIG_EXT4_FS_POSIX_ACL and CONFIG_EXT4_FS_SECURITY disabled, whereas the stock Ubuntu config enables both. This difference was resolved in audit2 below; audit1 remains an unchanged historical snapshot.
.IP \(bu 2
The candidate retains built-in NVMe, device mapper, dm-crypt, ext4, i915, and initrd support and disables loadable modules. These symbols are necessary evidence, not proof of a usable LUKS/initramfs boot path.
.IP \(bu 2
The host reported debhelper and libdw-dev installed; libelf-dev was already installed. The earlier packaging failure remains part of the audit history. A later audit2 package build is recorded below.
.IP \(bu 2
The read-only verify-secure-boot.sh script produced a misleading module-signature warning on the stock kernel. Direct inspection of its readable config showed CONFIG_MODULE_SIG=y and CONFIG_MODULE_SIG_FORCE disabled. The script result is not treated as proof that signature support is absent.
.SS Build-dependency installation confirmed
.PP
The owner supplied the apt transaction log for the requested build dependencies. It reported 22 newly installed packages, zero upgrades, and zero removals. Current dpkg-query checks independently confirm debhelper 13.31ubuntu1, libdw-dev 0.194-4, and the previously installed libelf-dev 0.194-4 in the installed state. The transaction did not install a kernel or produce a kernel package.
.PP
The 22 installed packages were: autoconf, automake, autopoint, autotools-dev, debugedit, debhelper, dh-autoreconf, dh-strip-nondeterminism, dwz, gettext, intltool-debian, libarchive-cpio-perl, libarchive-zip-perl, libdebhelper-perl, libdw-dev, libfile-stripnondeterminism-perl, libltdl-dev, liblzma-dev, libmail-sendmail-perl, libsys-hostname-long-perl, libtool, and po-debconf.
.PP
The apt log listed 13 packages as upgradable and suggested autoremove for existing packages, including initramfs-tools components. Neither an upgrade nor autoremove was performed as part of this transaction; do not remove initramfs or recovery tooling during kernel bringup. The dependency installation cleared only the earlier packaging prerequisite failure. At that point, audit1 image signing, initramfs, and fallback boot remained unverified.
.bp
.SH FOLLOW-UP: AUDIT2 MONOLITHIC BUILD
.PP
After owner approval, audit2 retained CONFIG_MODULES disabled. The only resolved-config changes relative to audit1 were CONFIG_EXT4_FS_POSIX_ACL=y, CONFIG_EXT4_FS_SECURITY=y, and the local release suffix -lockdown-t14g3-audit2. Both ext4 features are built into the existing CONFIG_EXT4_FS=y driver; no loadable modules were enabled. The original audit1 config snapshot was preserved.
.SS Config checks
.IP \(bu 2
The two new required-symbol checks first failed on the audit1 config as expected. After updating the fragment and resolving Kconfig, make olddefconfig reported no config changes, make listnewconfig printed no new symbols, and make prepare refreshed a stale generated kernel.release from audit1 to audit2.
.IP \(bu 2
Audit2 release: 6.18.53-lockdown-t14g3-audit2. Required-symbol preflight: 73 passes, zero failures, one existing CHECKPOINT_RESTORE warning. Project config audit: zero required failures. The audit2 config snapshot exactly matches the build-tree .config with SHA-256 9a2b4b65abab887323e21f143de6aa04b13411a47f2b45ebed1fcb8b422c4071.
.SS Build and package result
.IP \(bu 2
make -j12 bzImage completed successfully and compiled fs/ext4/acl.o and fs/ext4/xattr_security.o. Its compiler log had no warnings or errors. The later binary package build also completed successfully and relinked the final image. Final bzImage SHA-256: f22e9344042fed8d4187f30dba027172720fb0af92b092ef650722a4dae2b068.
.IP \(bu 2
make -j12 bindeb-pkg produced linux-image-6.18.53-lockdown-t14g3-audit2_6.18.53-5_amd64.deb, SHA-256 69f117af1cf0295f0233fcce9f6cd1f87c8cfb46f07779b7a06d40f2fb8b7727. It also produced linux-libc-dev_6.18.53-5_amd64.deb, SHA-256 f28a9a197761363fa8b7b5884658c472c99d50b9868aeaa2be8744ec38ea26e1. No headers package was produced.
.IP \(bu 2
The kernel image package contains /boot/vmlinuz-6.18.53-lockdown-t14g3-audit2 and the matching config. Streaming extraction confirmed their hashes match the final bzImage and config snapshot. The package contains no .ko modules, consistent with CONFIG_MODULES disabled.
.IP \(bu 2
The packaging log contained seven nonfatal single-label maintainer-email warnings and two linker warnings that .note.package was discarded and package metadata ignored. These are not Kconfig warnings. There were no fatal build errors; the linker metadata warning remains recorded for provenance review.
.SS Installation boundary
.IP \(bu 2
The packaged image has no Secure Boot signature. dpkg-query reports audit2 is not installed. Its post-install script would run local hooks, including dracut initramfs generation and GRUB update; those effects have not been invoked. No candidate initramfs or GRUB entry has been generated. Signing, installation, fallback validation, and reboot remain separate steps.
.IP \(bu 2
The existing Ubuntu 7.0.0-31-generic kernel remains running under Secure Boot integrity lockdown. No stock-versus-audit2 runtime or external-monitor measurement has been performed.
.bp
.SH FOLLOW-UP: SIGNED AUDIT2 STAGING
.PP
After the audit2 build, the unsigned bzImage was signed with the owner's already enrolled Paulino Power MOK. The private key was used in place outside the repository and was neither copied into the repository nor printed in the report. No new key was enrolled and the original unsigned package was preserved.
.IP \(bu 2
The standalone signed image was staged outside the repository at /home/the-ascended1/.local/share/lockdown-kernel/audit2/vmlinuz-6.18.53-lockdown-t14g3-audit2.signed. Its SHA-256 is 50096768b9ccf5b258e4a5f4932b5863f5877b1592abbd9b3822a3c97c87db37. sbverify with the enrolled MOK public certificate reported Signature verification OK.
.IP \(bu 2
A separate signed image package was repacked at build/signed/linux-image-6.18.53-lockdown-t14g3-audit2_6.18.53-5_amd64.deb, SHA-256 7d4b7318ceeef06e70d7f038e540c11381efeb33b2637f011881855422313450. Its Package, Version, and Architecture fields match the original image package. Only the embedded vmlinuz payload and its control md5sum changed; the post-install script hash matches the original.
.IP \(bu 2
The kernel image extracted from the signed package has the same SHA-256 as the staged signed image and passes sbverify against the MOK certificate. All seven packaged payload checksums pass md5sum -c. This verifies the package contents, not a machine boot.
.IP \(bu 2
The host still runs Ubuntu 7.0.0-31-generic. The signed package is not installed, no audit2 initramfs exists, and /etc/default/grub still had GRUB_TIMEOUT_STYLE=hidden and GRUB_TIMEOUT=0 at the last read-only check. The owner was asked to make the GRUB menu visible with a 15-second timeout, leaving GRUB_DEFAULT=0, then run update-grub and report any errors before installation. That change was not yet confirmed in this report.
.IP \(bu 2
The installed dracut tooling lists crypt, lvm, systemd-cryptsetup, rootfs-block, and related modules, but their presence in the tool installation is not evidence that a future audit2 initramfs contains the correct LUKS/LVM unlock path. Inspect the generated candidate initramfs after installing the signed package and before rebooting.
.PP
The private MOK key currently resides in the owner's home directory with mode 0600. This was not changed during signing. For a production trust boundary, review offline/encrypted key custody separately; signing success does not establish safe key storage.
.SH FOLLOW-UP: VISIBLE GRUB FALLBACK PREPARATION
.PP
The owner changed /etc/default/grub to GRUB_DEFAULT=0, GRUB_TIMEOUT_STYLE=menu, and GRUB_TIMEOUT=15, then ran update-grub. The owner-provided command output ended successfully and listed Ubuntu 7.0.0-31-generic and 7.0.0-29-generic images with their initramfs files, plus the older 6.18.53 entries. A subsequent read-only check of /etc/default/grub confirmed those three settings; the machine still runs Ubuntu 7.0.0-31-generic. The existing GRUB configuration is root-readable only, so its complete generated content was not independently inspected in this session. The visible-menu configuration and stock entries are confirmed, but an actual fallback selection has not yet been boot-tested.
.PP
The update-grub output warned that os-prober was disabled. That warning concerns discovery of other operating systems; the reported Ubuntu stock entries were generated. No bootloader entry was removed. /boot reported approximately 1.6 GiB available before candidate installation.
.PP
The signed audit2 image package remains uninstalled and its candidate initramfs and GRUB entry remain absent. The image package post-install script invokes host kernel hooks. The dracut hook is configured to generate /boot/initrd.img-6.18.53-lockdown-t14g3-audit2 and the GRUB hook to run update-grub; kdump-tools is also present and may run. These are expectations from script inspection, not completed actions. Installation output and generated artifacts require review before any reboot.
.bp
.SH FOLLOW-UP: SIGNED AUDIT2 INSTALLATION
.PP
The owner installed only the signed audit2 image package with dpkg. The owner-provided log shows unpacking and setup, dracut generation of /boot/initrd.img-6.18.53-lockdown-t14g3-audit2, kdump-tools generation of a separate /var/lib/kdump/initrd.img-6.18.53-lockdown-t14g3-audit2, and update-grub discovery of the candidate alongside Ubuntu 7.0.0-31-generic and 7.0.0-29-generic. The log ended with GRUB done; it also reported missing modules.order and kernel crypto module directories, plus the pre-existing os-prober warning.
.PP
A subsequent local read-only check reports the package as install ok installed and dpkg --audit printed no problems. The installed /boot/vmlinuz-6.18.53-lockdown-t14g3-audit2 has SHA-256 50096768b9ccf5b258e4a5f4932b5863f5877b1592abbd9b3822a3c97c87db37, exactly matching the staged signed image; sbverify with the enrolled MOK certificate reports Signature verification OK. The installed config SHA-256 is 9a2b4b65abab887323e21f143de6aa04b13411a47f2b45ebed1fcb8b422c4071, matching the audited snapshot. /boot contains a roughly 25 MiB candidate initramfs. The machine still runs Ubuntu 7.0.0-31-generic, and /boot has approximately 1.6 GiB free.
.PP
The candidate config explicitly disables CONFIG_MODULES; the /lib/modules candidate directory contains built-in metadata and an empty modules.dep, but no loadable .ko tree or modules.order. This explains why module-oriented depmod and kdump scripts emit the reported missing-file warnings. It does not prove the dracut image contains the userspace, configuration, and executable path required to unlock LUKS, activate LVM, and mount root. Both /boot/initrd.img-6.18.53-lockdown-t14g3-audit2 and /boot/grub/grub.cfg have mode 0600, preventing independent contents inspection without privileged owner assistance. Reboot is deferred until those artifacts are inspected.
.SS Owner-provided initramfs and GRUB listings
.PP
The owner supplied privileged lsinitrd and GRUB excerpts. The 25 MiB candidate initramfs reports dracut 110 and includes Intel microcode, the crypt, dm, lvm, systemd-cryptsetup, rootfs-block, and systemd initrd modules. Its file list contains etc/crypttab; etc/cmdline.d/20-crypt.conf, 20-lvm.conf, and 20-root-dev.conf; systemd-cryptsetup and lvm binaries; LVM rules; and crypt and LVM dracut hooks. The displayed embedded command line identifies rd.lvm.lv=ubuntu-vg/ubuntu-lv and root=/dev/mapper/ubuntu--vg-ubuntu--lv with ext4, matching the host root mapping. The installed kernel config also builds in NVMe, dm-crypt, ext4, AES, and XTS support. This is strong static evidence for the root storage path, not a successful boot test.
.PP
The supplied GRUB excerpt shows a normal candidate entry using /vmlinuz-6.18.53-lockdown-t14g3-audit2 and /initrd.img-6.18.53-lockdown-t14g3-audit2 with root=/dev/mapper/ubuntu--vg-ubuntu--lv; a recovery entry is also present. The excerpt did not include the first top-level GRUB linux line, so the effective default kernel remains to be independently confirmed. The lsinitrd listing did not show the contents of 20-crypt.conf or etc/crypttab, so the embedded LUKS UUID and unlock mapping remain to be checked before any reboot. Root-only file permissions are retained; the owner should provide targeted read-only output rather than changing permissions.
.SS Root-unlock and default-entry confirmation
.PP
The owner supplied the contents of the two requested initramfs files. etc/cmdline.d/20-crypt.conf specifies rd.luks.uuid=luks-6dc6712f-ec48-4782-a37a-9cef06b82a0d. Its etc/crypttab maps dm_crypt-0 to /dev/disk/by-uuid/6dc6712f-ec48-4782-a37a-9cef06b82a0d with a passphrase prompt (none) and luks option. This UUID matches the currently mounted root's LUKS2 container as reported by lsblk and the host /etc/crypttab. The first linux command in the generated GRUB configuration points to /vmlinuz-7.0.0-31-generic and the correct LVM root. GRUB_DEFAULT=0, GRUB_TIMEOUT_STYLE=menu, and GRUB_TIMEOUT=15 remain configured, so the normal default path is the stock Ubuntu kernel; the custom kernel requires a deliberate menu selection.
.PP
Pre-boot static checks covered the installed image's signature and audited config, its GRUB image/initramfs association, the LUKS UUID, LVM root, and available userspace and built-in storage/crypto support. They did not validate the complete runtime boot, graphical display, Secure Boot acceptance of this MOK at GRUB, LUKS passphrase handling, or fallback selection under fault. A supervised candidate boot was subsequently performed while retaining the stock default.
.SS Stock-kernel warning log provenance
.PP
After the first-boot instructions, the owner supplied kernel warning-log lines but no uname output. A local read-only check showed the machine still running 7.0.0-31-generic with boot ID 0d4ebd1d-02f5-4fc5-bd73-da7407ba1da2, started at 01:38:46 on 23 September 2026, approximately three hours before the audit2 package was installed. The candidate was then booted and its journal was supplied for analysis.
.SS Audit2 first-boot failure
.PP
The audit2 kernel reported CONFIG_NR_CPUS=2 at build time and brought up only two processors, while the stock kernel brings up all twelve CPUs. This is a confirmed configuration defect, not an ACPI or hardware limitation.
.PP
The candidate entered emergency mode because required runtime support was absent. Snap mounts repeatedly failed with "failed to setup loop device", indicating missing loop-device support. The EFI FAT filesystem also reported "codepage cp437 not found", which prevented normal EFI-partition mounting. The installed candidate module tree contained only metadata and no loadable .ko files, consistent with its monolithic CONFIG_MODULES=n policy; omitted built-in features still remain fatal even in a monolithic image.
.PP
The same boot exposed additional hardware-function failures. i915 could not load i915/adlp_guc_70.bin and declared the GPU wedged. The external MediaTek MT7921U repeatedly timed out while obtaining its firmware patch semaphore and ended with "hardware init failed". UCSI reported that the USB-C role switch was unavailable. autofs4 was also absent. These are separate from the CPU-count defect and must be resolved or explicitly accepted before another candidate boot.
.PP
The candidate's CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y explains why Secure Boot was enabled without integrity lockdown. The stock Ubuntu kernel, by contrast, reported that it was locked down from EFI Secure Boot mode. No candidate runtime integrity or IMA success should be claimed from this result.
.PP
The first candidate boot therefore failed functional validation. Do not select audit2 again until the resolved configuration and initramfs are re-audited for CPU capacity, loop devices, FAT/NLS support, Intel graphics firmware availability, MT7921U firmware availability, and the intended lockdown/integrity policy.
.SH FOLLOW-UP: CORRECTED AUDIT2 CONFIGURATION AND REBUILD ATTEMPT
.PP
At the owner's direction, the configuration was corrected for the confirmed audit2 first-boot defects and a new build was started. The owner authorized configuration correction, rebuilding and installation work, and pre-reboot testing, while retaining the reboot decision. No reboot was performed during this update.
.SS Configuration changes applied
.IP \(bu 2
config/hardened.config now requests CONFIG_NR_CPUS=64, providing headroom above the machine's twelve logical CPUs. Kconfig normalization of the merged Ubuntu base configuration resolved the effective build configuration to CONFIG_NR_CPUS=8192. That value is larger than requested but satisfies the boot requirement; the important result is that it is not the defective value of 2.
.IP \(bu 2
The lockdown policy was changed from CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y to CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y. This aligns the candidate's compile-time policy with the owner's requirement for integrity lockdown under Secure Boot. Runtime confirmation still requires booting the corrected image and checking the candidate journal and securityfs state.
.IP \(bu 2
CONFIG_SYSTEM_TRUSTED_KEYS and CONFIG_SYSTEM_REVOCATION_KEYS were explicitly set to empty strings so the kernel source would not attempt to read unavailable Ubuntu certificate paths during the standalone build. This is a build-input correction, not evidence that the candidate trusts no keys at runtime; the final keyring and Secure Boot behavior still require runtime inspection.
.IP \(bu 2
CONFIG_BLK_DEV_LOOP=y and CONFIG_BLK_DEV_LOOP_MIN_COUNT=8 were enabled to restore loop devices required by Snap and other image-backed mounts. CONFIG_SQUASHFS=y, CONFIG_SQUASHFS_XZ=y, and CONFIG_SQUASHFS_ZSTD=y were enabled for the corresponding compressed Snap images.
.IP \(bu 2
CONFIG_NLS_CODEPAGE_437=y was enabled to address the EFI FAT error "codepage cp437 not found". CONFIG_FW_LOADER_COMPRESS=y and CONFIG_FW_LOADER_COMPRESS_ZSTD=y were enabled because the host firmware inventory contains compressed .zst firmware, including Intel i915 and MediaTek firmware paths.
.IP \(bu 2
CONFIG_AUTOFS_FS=y was enabled to restore the autofs support that the failed boot reported as missing. The MediaTek MT7921U timeouts remain a hardware/firmware path to validate after the corrected image is booted; enabling the compressed firmware loader is necessary but does not prove successful device initialization.
.IP \(bu 2
config/required-symbols.txt was extended with the required loop, SquashFS, FAT codepage, compressed-firmware, and autofs symbols. scripts/preflight-check.sh was extended with a numeric minimum check requiring CONFIG_NR_CPUS to be at least 12. The existing project audit and boot-critical validation scripts remain separate checks.
.SS Corrected build evidence
.PP
The build was invoked with the project build script using profile hardened and the running Ubuntu kernel's /boot/config-7.0.0-31-generic as the base configuration. Kconfig resolution completed with all required boolean checks passing and the new numeric CPU check reporting CONFIG_NR_CPUS=8192. The build script also reported CONFIG_MODULES disabled, preserving the intentionally monolithic policy.
.PP
The first corrected packaging attempt exposed a workflow defect: deb-pkg requires Git metadata, but the extracted 6.18.53 source tree is not a Git repository. The project build script was corrected to use bindeb-pkg, which does not require the source tree to be a Git repository. The second corrected build passed the previous certificate-path stage and proceeded through compilation of the kernel subsystems, including loop, SquashFS, NLS cp437, autofs, firmware-loader compression, i915, and lockdown code.
.PP
The owner then intentionally interrupted the long-running compilation before final linking and package creation. The interrupted session produced no new package and did not install or alter the existing audit2 package. Read-only process inspection after interruption found no remaining build-kernel or make process. The only package artifacts found were the earlier 6.18.53-5 packages dated before this rebuild attempt. The generated build/linux-6.18.53/.config remains an intermediate build artifact and is not by itself a bootable kernel or a completed candidate.
.SS Installation and reboot boundary
.PP
The installed package remains linux-image-6.18.53-lockdown-t14g3-audit2 version 6.18.53-5, the earlier candidate whose first boot failed. The machine remains running Ubuntu 7.0.0-31-generic. No corrected image was installed, no corrected initramfs or GRUB entry was generated, and no reboot was performed. The earlier audit2 image must not be selected as a substitute for the incomplete corrected build.
.PP
The corrected configuration has not passed final package-level verification because the build was interrupted. Before any future installation, complete the build, identify the newly generated package by timestamp and checksum, run the project audit-config and validate-boot-critical checks against the final .config, install only after reviewing the package, sign the installed image with the enrolled MOK, inspect the generated initramfs for firmware and root-unlock paths, verify that the stock kernel remains GRUB_DEFAULT=0, and then stop for the owner's explicit reboot decision.
.SS Corrected build completion and current reboot boundary
.PP
The interrupted corrected build was resumed on 23 September 2026. The first resumed attempt reached final kernel linking but stopped because the host did not provide gawk. This was a host-tool failure, not a kernel-source or configuration failure. The kernel's generate_builtin_ranges.awk script uses the gawk-specific asorti() and strtonum() functions, so the installed mawk implementation was not a valid substitute. The official gawk package was extracted into a temporary user-space directory and supplied through PATH; no system package installation was completed and no reboot occurred.
.PP
With gawk available, the build completed through final vmlinux linking, bzImage generation, modules.builtin.ranges generation, and Debian packaging. The resulting candidate is linux-image-6.18.53-lockdown-t14g3-audit2 version 6.18.53-10 for amd64. The image package is build/linux-image-6.18.53-lockdown-t14g3-audit2_6.18.53-10_amd64.deb and its SHA-256 is 53417122650891370bc2350feac388d3e922909de54b25fb83f970edd3275d7f. A matching linux-libc-dev package and a debug package were also produced; neither is required for the boot candidate installation.
.PP
Final static checks against build/linux-6.18.53/.config passed. audit-config.sh reported zero required checks failed. validate-boot-critical.sh reported pass=82, fail=0, warn=0. scripts/preflight-check.sh reported pass=83, fail=0, warn=0, including effective CONFIG_NR_CPUS=8192, which is above the required twelve logical CPUs. The final configuration retains CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y, built-in loop/SquashFS/NLS cp437/autofs support, compressed firmware-loader support, CONFIG_MODULES=n, and the other corrected boot-critical symbols.
.PP
The package has not yet been installed because sudo requires interactive local authentication. Therefore the older installed version 6.18.53-5 remains the active installed audit2 candidate, the corrected initramfs and GRUB entry do not yet exist, and the running kernel remains Ubuntu 7.0.0-31-generic. The machine is not yet reboot-ready into the corrected candidate. Installation, MOK signing, initramfs inspection, GRUB fallback verification, and the owner's manual reboot decision remain separate pending actions. No reboot, grub-reboot, or default-entry change was performed.
.SS Host tooling remediation
.PP
After the build incident review, the owner installed the previously missing host tools system-wide. Verification reported git version 2.53.0 and GNU Awk 5.3.2, API 4.0. This resolves the two recurring build-environment gaps identified in this audit: Git metadata required by the deb-pkg workflow and GNU Awk functions required by scripts/generate_builtin_ranges.awk. Future kernel builds should use the installed tools directly rather than the temporary user-space gawk extraction or a bindeb-pkg-only workaround. This remediation does not alter the kernel image, installed kernel selection, Secure Boot state, initramfs, GRUB configuration, or reboot status.
.SH FOLLOW-UP: AUDIT3 SOURCE AND CONFIGURATION, 24 SEPTEMBER 2026
.PP
The owner approved a controlled replacement sequence: verify and freshly extract source, use a unique release identity, regenerate and gate the resolved config, rebuild and sign the final package, inspect the installed initramfs and GRUB state, and then supervise one boot and the full hardware checklist. Swap was explicitly excluded from changes.
.SS Source provenance
.PP
The local linux-6.18.53.tar.xz has SHA-256 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0. The detached linux-6.18.53.tar.sign was retrieved from kernel.org and verified against the decompressed tar stream with GPG, because kernel.org signs the uncompressed tar archive. GPG reported GOODSIG and VALIDSIG for Greg Kroah-Hartman, key ID 38DBBDC86092693E and full fingerprint 647F28654894E3BD457199BE38DBBDC86092693E. The full fingerprint matches kernel.org's published release-signing fingerprint. GPG also reported that this temporary keyring had no personal trust certification; fingerprint comparison to the publisher's site supplied the independent identity check. The signature, verification output, and fresh extraction are in build/audit3-final2; the previous extracted build tree was not used for the final attempt.
.SS Resolved configuration and policy tradeoff
.PP
The release identity is 6.18.53-lockdown-t14g3-audit3, separate from the installed failed audit2 package. A stock Ubuntu 7.0.0-31-generic base config was merged with config/hardened.config, then Linux 6.18.53 olddefconfig resolved it. The resulting config SHA-256 is b79bd6c710935f64c00815e343bb051775900b4b7acc14bbb087a68ffb1d9335. The boot-critical preflight passed 83 checks with zero failures and warnings; the separate boot-critical validator passed 82 checks with zero failures and warnings. The new security-policy gate passed 26 checks, including force-integrity lockdown, IOMMU/IRQ remapping, disabled module loading, ACPI debugger, debugfs, KGDB/KDB, dynamic debug, and function/stack tracing. The project read-only config audit reported zero required failures.
.PP
The full audit3 resolved config is stored as config/candidate-6.18.53-lockdown-t14g3-audit3.config. The prior corrected but uninstalled 6.18.53-10 audit2 config was also snapshotted separately, with SHA-256 9f912964bffebbef0c867bba165e8d92807884d47f38ba90a2d531e17b465936. Their 127-line diffconfig output is stored as config/audit2-uninstalled-10-to-audit3.diffconfig. It records the unique release, 64-CPU limit, and removal of inherited debug interfaces; the 32/16-bit mmap ASLR defaults are unchanged.
.PP
An initial attempt to turn off CONFIG_EXPERT did disable CONFIG_DEBUG_KERNEL, but it also lowered default mmap ASLR entropy from 32/16 bits to 28/8. That attempt was interrupted before packaging. The final profile retains CONFIG_EXPERT=y and the 32/16-bit ASLR defaults, which means the umbrella CONFIG_DEBUG_KERNEL=y remains selected by Kconfig. It disables and gates the actual debugging interfaces instead. This deliberate exception to the earlier blanket DEBUG_KERNEL exclusion is recorded in the project reference; neither the interrupted attempt nor the older audit2 image is a final audit3 package.
.PP
The current swap file remains on the LUKS-backed ext4 root filesystem and was not modified. The stock kernel was still running before installation, Secure Boot remained enabled, and GRUB_DEFAULT=0 with a visible menu and 15-second timeout remained configured. grub-editenv read-back produced the known hostdisk warning and an empty next_entry; no one-shot boot selection should be treated as verified from that tool output.
.SS Audit3 package completion and signature verification
.PP
The clean build completed successfully on 24 September 2026 through both kallsyms links, final vmlinux, bzImage generation, and Debian packaging. The binary package is linux-image-6.18.53-lockdown-t14g3-audit3, version 6.18.53-11, architecture amd64. The unsigned image package SHA-256 is 8025d9ca33106a294e59318e9c52ebd199f403b05ccb12b57c9ef840c4cfe68a. Its embedded config exactly matches the saved audit3 config and passed the 83-check boot preflight and 26-check security gate again after packaging.
.PP
The kernel image inside the completed package was signed using the existing Paulino Power MOK certificate, whose SHA-256 fingerprint (hexadecimal groups) is 2DA9363130223973 C4396EE4EA524841 545D4E732C98ED52 C69D15F4A4361DE1. The private key was neither displayed nor modified. Package md5sums were regenerated and the package was rebuilt with root ownership. A fresh extraction of the final package passed sbverify against that certificate, all package checksums, and an exact config comparison. There are no loadable .ko files in the package.
.PP
Installable artifact: build/audit3-final2/signed/linux-image-6.18.53-lockdown-t14g3-audit3_6.18.53-11_amd64.deb, size 73402792 bytes. Its SHA-256 is d8ca142babfac3d0e408324ecae453532a086a1f27e57e7378966d7394794da6. The signed kernel image SHA-256 is 456f636c79f1eabdce67e331ac4477d15548df058fa0b650582d70599a99ea87. The signature is on the contained UEFI kernel image; this is not an OpenPGP signature on the .deb container. The signed package has a separate directory from the original unsigned build output, and only that exact signed package is intended for installation.
.PP
Installation remains pending because sudo requires interactive local authentication. Thus no audit3 initramfs or GRUB entry has been generated or inspected, and audit3 has not booted. The running kernel remains 7.0.0-31-generic. A MOK enrollment check reported that the certificate is already enrolled, while also warning that the kernel trusted keyring was unavailable; runtime acceptance still requires the supervised boot. The general build helper now runs both config gates, checks for gawk/Git, gives the correct decompressed-tar signature command, and warns against broad package globs. Automated source provenance/freshness enforcement in that helper remains an open issue; this release used the separately verified fresh extraction.
.SS Audit3 installation and remaining preboot hold, 24 September 2026
.PP
The owner subsequently installed the exact signed audit3 package. Live dpkg status confirms version 6.18.53-11 is installed. The installed /boot/vmlinuz-6.18.53-lockdown-t14g3-audit3 passes sbverify with the existing MOK certificate and has SHA-256 456f636c79f1eabdce67e331ac4477d15548df058fa0b650582d70599a99ea87, matching the signed artifact. The installed config has SHA-256 b79bd6c710935f64c00815e343bb051775900b4b7acc14bbb087a68ffb1d9335, matches the saved config exactly, and passes 83 boot checks and 26 security-policy checks.
.PP
The installation generated the main /boot/initrd.img candidate and a separate kdump initramfs, and completed GRUB generation. Missing modules.order and kernel/crypto directory warnings are consistent with the monolithic CONFIG_MODULES=n package; they do not establish missing built-in crypto support. Numerous firmware warnings occurred during kdump image generation and include devices outside this machine's inventory. They must not be treated as proof that the main initramfs contains the required firmware. Host filesystem checks find the i915 Alder Lake DMC/GuC and Tiger Lake HuC files, MediaTek MT7961 firmware pair, and SOF Alder Lake firmware; candidate initramfs inclusion remains unverified.
.PP
The candidate initramfs and grub.cfg are root-readable only. Noninteractive sudo remains unavailable, so inspection of their contents requires the owner's local authentication. scripts/inspect-audit3-boot.sh collects only read-only evidence: dracut modules, relevant firmware and root-path listings, crypttab and generated command-line configuration, and GRUB selection/menu state. It does not print keyfile contents, alter boot selection, or reboot.
.PP
Stock Ubuntu 7.0.0-34-generic is also now installed and appears before 7.0.0-31-generic in the installation's GRUB discovery log. GRUB_DEFAULT remains 0, but the generated default has not been read; do not claim that it still selects 31. The running kernel remains the known-good 7.0.0-31-generic, which must remain available for recovery. Secure Boot is enabled. No candidate boot, fallback boot test, or hardware validation has occurred; swap remains unchanged.
.SS Privileged preboot inspection: firmware omission found
.PP
The owner supplied the read-only privileged inspection. The initial audit3 initramfs SHA-256 is 50bca90a754dc6e9b0e087032ef911d4e63b931abf6555c2e9048cf8f64ebeec. Its contents confirm Intel microcode, crypt/dm/lvm/systemd-cryptsetup/rootfs-block, LUKS UUID 6dc6712f-ec48-4782-a37a-9cef06b82a0d, and the ubuntu-vg/ubuntu-lv ext4 root configuration. Generated GRUB default 0 selects stock 7.0.0-34-generic; both known-good 7.0.0-31-generic and audit3 entries exist with matching initrd paths. Local-sudo grubenv read-back reports empty next_entry without the historical hostdisk error. No one-shot boot is queued.
.PP
However, the supplied initramfs listing contains no i915, MediaTek MT7961, or SOF firmware paths. This is a preboot blocker for this monolithic candidate, not a successful firmware gate. A nonprivileged reproduction with the installed dracut-install utility, the audit3 module directory, and explicit i915/mt7921u driver names returned success but copied no firmware. modinfo identifies i915 as built-in and reports the expected MT7961 firmware names. Built-in driver discovery is therefore insufficient for firmware collection in this installed workflow.
.PP
Prepared correction: config/60-lockdown-audit3-firmware.conf explicitly adds the three Alder Lake i915 firmware files, the two MT7961 Wi-Fi firmware files, SOF Alder Lake firmware and generic HDA topologies. The drop-in applies only when the target kernel is exactly 6.18.53-lockdown-t14g3-audit3. A staging test confirmed all nine requested files copy byte-for-byte, including the SOF symlink target; checks confirmed the drop-in leaves stock 31, stock 34, and audit2 unchanged. Current stock audio uses snd_hda_intel/ALC257; SOF active-driver claims remain unproven, and no audio driver override was added.
.PP
Installing this drop-in and regenerating only the audit3 main initramfs require local sudo. Preserve the existing initramfs first, then repeat the read-only inspection and record its new checksum and actual firmware contents. No kernel rebuild or image re-signing is required for this initramfs-only correction. Neither the signed image nor GRUB selection nor swap was changed in preparing it. The supervised boot remains on hold until the generated firmware contents pass inspection.
.SS Firmware correction verified: supervised test ready
.PP
The owner installed the exact-release firmware drop-in and regenerated the audit3 main initramfs. Supplied privileged inspection reports SHA-256 de381c6969713e94ea2200cafbe9a869ae217076f4f87478e3bebc50de55ff7d. It lists adlp_dmc.bin.zst, adlp_guc_70.bin.zst, tgl_huc.bin.zst, both MT7961 Wi-Fi firmware files, sof-adl.ri and its intel-signed target, and the generic HDA topology plus 2ch/4ch variants. Intel microcode and the correct LUKS UUID, LVM volume and ext4 root configuration remain present. Live stat confirms a 27331595-byte replacement and a root-only 26383235-byte before-firmware backup.
.PP
Live comparison confirms the installed dracut drop-in matches the repository. The installed kernel still passes MOK signature verification, its image/config hashes remain unchanged, Secure Boot is enabled, the boot preflight passes 83/0/0, the boot-critical validator passes 82/0/0, and the security gate passes all 26 checks. The read-only configuration audit has zero required failures. The remaining modules.order warning did not prevent regeneration and does not indicate absent loadable modules in this CONFIG_MODULES=n build.
.PP
The static firmware omission is closed. One physically supervised manual audit3 test may now proceed, with stock 7.0.0-34-generic remaining the normal GRUB default and known-good 7.0.0-31-generic available for recovery. next_entry is empty. No reboot has been performed; root unlock, runtime lockdown, firmware initialization, hardware behavior, suspend/resume, fallback and power measurements remain unvalidated. Swap was not changed.
.SS First audit3 boot: essential paths work, unrelated drivers warn
.PP
The owner supplied the first supervised candidate journal; the currently live kernel is 6.18.53-lockdown-t14g3-audit3, boot ID 7c6b86be-90b4-42cf-9fb1-a7c33d0674b6. Secure Boot is enabled and securityfs reports [integrity]. The host has twelve CPUs, AppArmor is enabled in the active LSM list, LUKS/LVM ext4 root reached userspace, and systemctl --failed reports zero units. TPM 2.0 was detected. The live kernel log confirms DMAR translation and interrupt remapping. /swap.img remains on the encrypted root, unchanged. Because CONFIG_MODULES=n, the runtime modules_disabled sysctl file is absent by design.
.PP
i915 initialized on Alder Lake with DMC firmware, GuC 70.49.4 and HuC 7.9.3 authenticated and GuC submission enabled; the supplied excerpt shows no wedge. The external MT7921U initialized with firmware and live `iw` output shows association to Technocopia plus a default route. No active end-to-end network probe is recorded. Audio enumerated the HDA/ALC257 codec; speakers, mic and headphones have not been physically tested. Physical keyboard/TrackPoint/touchpad and brightness checks, external HDMI/USB-C display, Snap mounts, Thunderbolt policy, suspend/resume, and fallback to stock remain open.
.PP
The boot also exposed configuration drift: CONFIG_MTD_NETtel=y initializes the SnapGear NETtel flash-map driver, maps physical 0x20000000 despite the kernel reporting RAM there, triggers WARNING at __ioremap_caller and fails its nonexistent BOOTCS probe. This warning did not prevent boot but should be removed before calling the image clean. CONFIG_IEEE802154_HWSIM=y and CONFIG_IEEE802154_FAKELB=y expose synthetic wpan interfaces and generate repeating encryption-failed -22 messages about once per minute. These simulator paths are not in the documented hardware inventory. A fresh audit should disable these three options, resolve Kconfig, rerun gates, and produce a separately identified signed candidate. The current candidate remains the running system while physical checklist items are gathered; no such config change has yet been made.
.PP
GRUB default remains stock 7.0.0-34-generic and known-good 7.0.0-31-generic remains available. This first candidate boot does not validate stock fallback. Candidate runtime is partially validated; outstanding physical and power tests are not inferred from driver binding or static checks.
.PP
Additional live checks on this same boot show the EFI system partition mounted as VFAT with codepage=437, Intel microcode 0x43b, and installed Snap images mounted as SquashFS loop devices. A one-packet ICMP test to the local Wi-Fi gateway passed with zero packet loss. Broader connectivity, NVMe health, physical internal/external display and input, audio, USB-C, suspend/resume, and stock fallback testing remain pending.
.SH AUDIT4 NARROW CONFIGURATION REVISION, 25 SEPTEMBER 2026
.SS Provenance and immutable rollback
.PP
Audit4 begins from the installed and booted audit3 resolved config, whose repository snapshot and /boot/config matched byte-for-byte at SHA-256 b79bd6c710935f64c00815e343bb051775900b4b7acc14bbb087a68ffb1d9335. The audit3 build tree, package, image, config, firmware drop-in, and installed GRUB entry were not modified. The original Linux 6.18.53 archive has SHA-256 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0. Its detached uncompressed-tar signature verified against Greg Kroah-Hartman's kernel.org signing key fingerprint 647F28654894E3BD457199BE38DBBDC86092693E before extraction into a distinct build/audit4-final tree.
.SS Exact resolved Kconfig delta
.PP
The release suffix changes from -lockdown-t14g3-audit3 to -lockdown-t14g3-audit4. These independent audit3 built-ins now resolve disabled: CONFIG_FB_VIA, CONFIG_MSI_EC, CONFIG_INPUT_KEYSPAN_REMOTE, CONFIG_USB_SERIAL_KEYSPAN_PDA, CONFIG_USB_SERIAL_KEYSPAN, CONFIG_USB_EMI62, CONFIG_USB_EMI26, CONFIG_USB_ISIGHTFW, CONFIG_SLIP, and CONFIG_KVM_AMD. Four requested child symbols disappear from the resolved config because their parent is disabled: CONFIG_FB_VIA_X_COMPATIBILITY and CONFIG_SLIP_COMPRESSED, CONFIG_SLIP_SMART, CONFIG_SLIP_MODE_SLIP6. Two further dependent symbols disappear: CONFIG_FB_VIA_DIRECT_PROCFS (previously disabled) and CONFIG_VIDEO_VIA_CAMERA (previously built-in; depends on FB_VIA and VIDEO_DEV). This last dependency is the only additional built-in removed. No other resolved symbol changed. Audit4's resolved config SHA-256 is 73ff44a78829bb933e02ddb13a8eea8e574c4277cb90c805ca52bfad34ae305d.
.PP
The live machine identifies as Lenovo 21AJS1GL06 with Intel VGA 8086:46a8, Intel USB/xHCI, Intel HDA, Samsung NVMe, and a MediaTek 0e8d:7961 USB Wi-Fi adapter. No VIA graphics/camera, MSI embedded controller, Keyspan remote/serial, EMI26/62 audio, or iSight camera is in the current inventory. The intended networking does not use serial-line IP; an Intel CPU cannot execute the AMD KVM backend, while Intel KVM stays. This supports the specific removals without treating the current USB list as proof that all future hotplug devices are impossible.
.PP
Intel KVM, CFG80211, Intel i915, NVMe, dm-crypt, ThinkPad ACPI, and Intel/AMD/Hygon/Centaur/Zhaoxin CPU support remain built-in. CONFIG_MODULES and CONFIG_LOCALVERSION_AUTO remain disabled. The Kconfig resolver reported no new prompts. The boot preflight passed 83/0/0, security policy 26/0, boot-critical validation 82/0/0, and the project configuration audit reported zero required failures. These are static gates, not an audit4 boot result.
.SS Regulatory database and early firmware
.PP
The live audit3 journal logged a direct regulatory.db firmware load failure (-2) before the kernel started /init and before the real root was mounted. The owner supplied a privileged lsinitrd check of the audit3 image: no regulatory.db or regulatory.db.p7s path matched, and a separate full lsinitrd read exited zero. Thus neither file is listed in the audit3 initramfs. Both files exist on the real root under /lib/firmware. An OpenSSL CMS check with binary content mode verified the database signature. The signer CN=wens and serial 61C038651AABDCF94BD0AC7FF06C7248DB18C600 exactly match the regulatory certificate reported loaded by the running kernel. These facts support missing early firmware as the reason for the -2 warning, not a signature-validation failure. The audit4-only dracut drop-in stages both files together with the nine graphics, Wi-Fi and audio firmware files already required by audit3. CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=y and CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS=y are unchanged. Actual audit4 initramfs contents and post-boot regulatory behavior remain to be checked after installation and a supervised boot.
.SS Package and deployment boundary
.PP
The separate audit4 bindeb-pkg build completed with exit status zero, including the final bzImage, image package, libc headers package, and optional debug package. It uses the reviewed config and a unique Debian package version 6.18.53-12. The unsigned image package has SHA-256 07f89f3605907d5ead4592633be5615b0d706f0a77983c7237a612ea4ef8ca7f. Its embedded config matches the reviewed snapshot byte-for-byte and the monolithic package contains no loadable .ko files. Build warnings concerned the local single-label Debian email domain, frame sizes in unchanged maple_tree and WireGuard code, and linker package metadata; no boot-critical compilation failure was reported.
.PP
The EFI image was signed in an isolated temporary extraction with the existing Paulino Power MOK. The signing helper's initial already-signed check falsely triggers on sbverify --list exit status even when the tool prints No signature table present; that output was confirmed before the helper's explicit override was used. No pre-existing image signature was replaced. A fresh extraction of the signed package passed all package md5sums, exact config comparison, and sbverify against the existing MOK certificate; no .ko files exist. Signed image SHA-256 is dc05dbabe29f3689b4692d75b85589104adcefc3dfd06245a583417f089b3962. Installable signed image package is build/audit4-final/signed/linux-image-6.18.53-lockdown-t14g3-audit4_6.18.53-12_amd64.deb, SHA-256 ca1cd1ae0d1f3e7b0909a40d0ef7e8dbfeb61ae37939d9cc63c41bbd3d37c54c.
.PP
A signed package, an installed image, a generated initramfs, a GRUB entry, and a successful boot are distinct states. At this record point audit4 installation requires local sudo authentication and has not been observed. Its exact-release dracut drop-in must be installed before dpkg so the generated initramfs includes the required firmware and signed regulatory database pair. The local grub-editenv read-back warns that hostdisk//dev/nvme0n1p2 is not found, so its displayed empty next_entry is not verified; do not schedule a one-shot GRUB boot based on that output. Use a supervised manual selection from the visible menu after privileged GRUB and initramfs checks. Do not set audit4 as the default, remove audit3 or stock recovery entries, alter swap, or reboot automatically.
.SH AUDIT5 SWAP, THUNDERBOLT, AND CONFIG FOLLOW-UP, 25 SEPTEMBER 2026
.SS Swap encryption is already in place
.PP
The active `swapon --show` entry is /swap.img, an 8 GiB file. `findmnt -T /swap.img` places it on the ext4 root LV /dev/mapper/ubuntu--vg-ubuntu--lv. `lsblk -s` traces that LV through dm_crypt-0 to /dev/nvme0n1p3, whose FSTYPE is crypto_LUKS; /etc/crypttab names dm_crypt-0 with the luks option. Thus swap writes traverse the existing LUKS-backed dm-crypt mapping. The filename alone does not mean unencrypted swap. No swap migration, key change, or swapon change was performed. A separate LV would not add an at-rest encryption boundary here.
.SS Thunderbolt PCI enumeration is not authorization
.PP
The running audit3 kernel remains 6.18.53-lockdown-t14g3-audit3. `boltctl list` and `boltctl domains` returned no entries. `lspci -nnk` shows the two Intel Thunderbolt 4 NHI PCI functions at 00:0d.2 and 00:0d.3, but neither has a kernel driver bound. The separate xHCI USB function at 00:0d.0 is bound to xhci_hcd. Audit3's resolved CONFIG_USB4 is disabled. This supports the claim that the running kernel is not driving Thunderbolt tunnels; it does not prove the functions are disabled in firmware or that pre-boot PCIe tunneling is blocked. Firmware exposes a ThinkLMI ThunderboltAccess setting, but its current_value is readable only by root and was not obtained. The unprivileged setting list did not reveal a distinct PCIe-tunneling control. Read the value with local sudo and inspect UEFI setup for a distinct control before making a firmware claim or change. No firmware setting was changed.
.SS Separate audit5 config candidate
.PP
The user requested removal of non-Lenovo vendor drivers and synthetic 802.15.4 radios. Audit4 already has CONFIG_KVM_AMD disabled, but is signed and unchanged. Audit5 starts from the complete audit4 resolved config, uses release suffix -lockdown-t14g3-audit5, and disables the Surface and Dell platform submenus, HP platform submenu plus HP iLO/watchdog, AcerHDF/Acer wireless/Acer WMI, and Apple SMC. It also disables CONFIG_IEEE802154 and CONFIG_MAC802154, which removes the fakelb, hwsim, and other dependent 802.15.4 paths. Kconfig resolution also removes child Surface, Dell/Alienware, HP and related dependent symbols. ThinkPad ACPI, Intel KVM, storage, graphics, Wi-Fi, audio, Type-C/DP, LUKS and TPM support remain. The exact full diff is available from the two resolved config snapshots; audit5 snapshot SHA-256 is 8f3e3df8bd683ae24ecf35e0c8e58115db52533c190b8b2113e5d6e738bdf411.
.PP
The same Linux 6.18.53 archive SHA-256 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0 had its detached uncompressed-tar signature freshly verified against the kernel.org-published Greg Kroah-Hartman key fingerprint 647F28654894E3BD457199BE38DBBDC86092693E, then was extracted to separate build/audit5-final source. Kconfig olddefconfig and listnewconfig returned no new prompts. The required preflight passed 83/0/0, production security gate 26/0, boot-critical gate 82/0/0, and project config audit found zero required failures. These are static configuration results only. Audit5 has not been installed or booted; the observed audit3 radio errors are not yet shown fixed at runtime. The unrelated audit3 CONFIG_MTD_NETtel warning remains outside this requested delta.
.SS Command trail and configuration excerpt
.PP
The earlier audit stages corrected the failed audit2 boot before hardware tuning continued. Audit2 exposed a two-CPU limit, missing loop support for Snap, absent CP437 FAT support, incorrect lockdown policy, and missing early firmware. Audit3 resolved the config, rebuilt with a unique release, staged firmware in initramfs, was signed and installed, and then reached userspace under integrity lockdown. The audit3 boot still showed unrelated-driver probes and synthetic wpan errors.
.nf
.ft CR
.ps 8
CONFIG_NR_CPUS=64                 # effective audit3 resolved to 8192
CONFIG_BLK_DEV_LOOP=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y
CONFIG_LOCALVERSION="-lockdown-t14g3-audit3"
.ps 10
.ft R
.fi
.PP
Audit4 used a separate release identity and removed the specifically reviewed unused devices, including the AMD KVM backend on this Intel CPU. Audit4 was built and signed, but is not installed or booted. Audit5 preserves it as a rollback candidate and layers the additional vendor and radio removals described below.
.nf
.ft CR
.ps 8
CONFIG_LOCALVERSION="-lockdown-t14g3-audit4"
# CONFIG_KVM_AMD is not set
# CONFIG_FB_VIA is not set
# CONFIG_MSI_EC is not set
# CONFIG_INPUT_KEYSPAN_REMOTE is not set
# CONFIG_USB_SERIAL_KEYSPAN is not set
# CONFIG_USB_EMI62 is not set
# CONFIG_USB_EMI26 is not set
# CONFIG_USB_ISIGHTFW is not set
# CONFIG_SLIP is not set
.ps 10
.ft R
.fi
.PP
The following excerpts preserve the commands used to establish storage and Thunderbolt state, verify upstream provenance, and resolve the audit5 candidate. The final firmware-value read requires local root authentication and remains pending.
.nf
.ft CR
.ps 8
$ swapon --show --output NAME,TYPE,SIZE,USED,PRIO
$ findmnt -T /swap.img -o SOURCE,FSTYPE,TARGET
$ lsblk -s -o NAME,TYPE,FSTYPE /dev/mapper/ubuntu--vg-ubuntu--lv

$ boltctl list
$ boltctl domains
$ lspci -k | grep -iA3 thunderbolt
$ fwupdmgr get-bios-settings ThunderboltAccess --json
$ sudo cat \e
    /sys/class/firmware-attributes/thinklmi/attributes/ThunderboltAccess/current_value

$ sha256sum linux-6.18.53.tar.xz
$ xz -cd linux-6.18.53.tar.xz | gpg --homedir build/audit5-verify-gnupg \e
    --verify build/audit3-final2/linux-6.18.53.tar.sign -
$ tar -xf linux-6.18.53.tar.xz -C build/audit5-final/linux-6.18.53 \e
    --strip-components=1

$ REPO=/home/the-ascended1/Lock_Down
$ SRC="$REPO/build/audit5-final/linux-6.18.53"
$ cp "$REPO/config/candidate-6.18.53-lockdown-t14g3-audit4.config" \e
    "$SRC/.config"
$ cd "$SRC"
$ env KCONFIG_CONFIG="$SRC/.config" \e
    bash scripts/kconfig/merge_config.sh -m .config \e
    "$REPO/config/hardened.config"
$ make olddefconfig
$ make listnewconfig
$ scripts/diffconfig \e
    "$REPO/config/candidate-6.18.53-lockdown-t14g3-audit4.config" .config
.ps 10
.ft R
.fi
.PP
The reviewed fragment expresses the requested reductions; Kconfig resolves the parent and child dependencies into the full snapshot.
.nf
.ft CR
.ps 8
CONFIG_LOCALVERSION="-lockdown-t14g3-audit5"
# CONFIG_SURFACE_PLATFORMS is not set
# CONFIG_X86_PLATFORM_DRIVERS_DELL is not set
# CONFIG_X86_PLATFORM_DRIVERS_HP is not set
# CONFIG_ACERHDF is not set
# CONFIG_ACER_WIRELESS is not set
# CONFIG_ACER_WMI is not set
# CONFIG_SENSORS_APPLESMC is not set
# CONFIG_IEEE802154 is not set
# CONFIG_MAC802154 is not set
.ps 10
.ft R
.fi
.PP
The effective audit5 config retains CONFIG_THINKPAD_ACPI=y and resolves CONFIG_IEEE802154_FAKELB and CONFIG_IEEE802154_HWSIM absent/disabled. Audit4 remains separately snapshotted and signed. The audit5 snapshot SHA-256 is recorded above.
.PP
The package build uses unique Debian package version 6.18.53-13 from the fresh audit5 tree. Its command is:
.nf
.ft CR
.ps 8
$ make -j12 bindeb-pkg KDEB_PKGVERSION=6.18.53-13
.ps 10
.ft R
.fi
.PP
The first build invocation reached the final vmlinux link without a recorded compiler diagnostic but its process ended before package creation. The incremental rerun also stopped without a completed package; audit5 has no installable artifact. No package success is inferred from the linker progress.
.SH AUDIT6 HARDWARE-REDUCTION CHECKPOINT, 27 SEPTEMBER 2026
.SS Intent, provenance, and baseline
.PP
The owner approved continued hardware-specific pruning, explicitly retaining Intel KVM and the ability to build further secure kernels. Every removed family is tied to live hardware evidence or an unused guest/test path. Audit6 is a checkpoint for static, package, and then supervised boot validation; it is not called near-minimal or runtime-validated. The working audit3 image, signed but uninstalled audit4 image, and stock fallback remain unchanged. Active /swap.img remains on the LUKS-backed root and was not changed.
.PP
Audit6 begins from the complete audit5 resolved config, SHA-256 8f3e3df8bd683ae24ecf35e0c8e58115db52533c190b8b2113e5d6e738bdf411, not an inventory-derived localmodconfig. The original 6.18.53 tar.xz SHA-256 remains 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0. The detached signature on the decompressed tar stream passed GPG verification with Greg Kroah-Hartman's 647F28654894E3BD457199BE38DBBDC86092693E release key before fresh extraction into build/audit6-final. The isolated keyring has no personal certification; the kernel.org-published fingerprint checked again on 27 September remains the signer-identity basis.
.SS Evidence and selected removals
.PP
The live PCI inventory shows Intel Alder Lake platform devices, Intel i915, Intel HDA, Intel USB/xHCI and SPI, and Samsung NVMe, but no PCI Ethernet, SATA, UFS, MMC, Memory Stick, CXL, RapidIO, or PCI endpoint controller. The only intended WLAN device remains MT7921U USB 0e8d:7961. /proc/mtd exposes only an mtdram test device and a NAND simulator. The CPU advertises VMX/EPT/VPID but no SGX/TDX flag. Current swap uses /swap.img, not zram. The Thunderbolt NHI PCI functions remain enumerated without a bound audit3 USB4 driver; firmware policy is still unverified.
.PP
The audit6 fragment disables Xen and Hyper-V guest-driver families, CXL, RapidIO, PCI endpoint, MTD (including the NETtel, mtdram and nandsim paths), PCI Ethernet and all non-MediaTek WLAN vendor menus. Disabling the SCSI low-level host-driver menu prevents unused iSCSI/FCoE offload drivers from selecting Ethernet back on; SCSI core, SCSI disk, USB mass-storage and UAS remain built in for recovery media. ATA, UFS, MMC, Memory Stick, InfiniBand, ISDN, ATM, ATA-over-Ethernet, null-block, NBD, inactive zram, SGX and TDX host support are also disabled. NoIOMMU VFIO bypass and the optional KVM virtualization-exception debug checker are excluded. KVM Intel host, Intel IOMMU/IRQ remapping, VFIO with IOMMU, and vhost acceleration remain for running VMs. Virtio guest drivers remain for testing this kernel inside a VM; they are distinct from the KVM host requirement. Hyper-V emulation inside KVM is not the removed Hyper-V guest-driver family.
.PP
DWARF debug information is disabled for this production-candidate build with CONFIG_DEBUG_INFO_NONE=y. Kallsyms remains for stack traces. This reduces build/debug-package cost; it is not claimed as a battery or runtime-security improvement.
.SS Resolved config and static gates
.PP
The unique release suffix is -lockdown-t14g3-audit6. olddefconfig and listnewconfig completed without new prompts. The full effective snapshot is config/candidate-6.18.53-lockdown-t14g3-audit6.config, SHA-256 88fab201f7a95a00e70f80d3ddfaa98e3cfbb6bde0826c75b4aee029940a7cb1. Audit5 had 9274 built-in =y selections; audit6 has 8173, a reduction of 1101. The full diffconfig has 1272 changed lines. This count is configuration breadth, not a measured attack-surface or power result.
.PP
The project config audit reports zero required failures. Boot-critical validation passed 82/0/0, required-symbol preflight passed 83/0/0, and the production security-policy gate passed 26 checks. The source tree .config matches the saved snapshot byte-for-byte. Explicit inspection confirms KVM_INTEL, INTEL_IOMMU, IRQ_REMAP, VFIO, VHOST, MT7921U, NVMe, DM_CRYPT, EFI_ESRT, SPI_INTEL_PCI, USB storage/UAS, USB Ethernet, loop/SquashFS, i915 and SOF/HDA remain enabled. The retired families resolve disabled; Ethernet initially stayed enabled due to SCSI offload selects, and only resolved disabled after closing that parent dependency.
.SS Reproducible command and config excerpts
.nf
.ft CR
.ps 8
$ sha256sum linux-6.18.53.tar.xz
$ set -o pipefail
$ xz -cd linux-6.18.53.tar.xz | gpg \e
    --homedir build/audit5-verify-gnupg --batch \e
    --verify build/audit3-final2/linux-6.18.53.tar.sign -
$ mkdir -p build/audit6-final/linux-6.18.53
$ tar -xf linux-6.18.53.tar.xz \e
    -C build/audit6-final/linux-6.18.53 --strip-components=1
$ cp config/candidate-6.18.53-lockdown-t14g3-audit5.config \e
    build/audit6-final/linux-6.18.53/.config
$ KCONFIG_CONFIG="$PWD/build/audit6-final/linux-6.18.53/.config" \e
    bash build/audit6-final/linux-6.18.53/scripts/kconfig/merge_config.sh \e
    -m -Q build/audit6-final/linux-6.18.53/.config config/hardened.config
$ make -C build/audit6-final/linux-6.18.53 olddefconfig
$ make -C build/audit6-final/linux-6.18.53 listnewconfig
$ make -C build/audit6-final/linux-6.18.53 -j12 bindeb-pkg \e
    KDEB_PKGVERSION=6.18.53-14
.ps 10
.ft R
.fi
.PP
Selected fragment assignments, checked against the effective snapshot:
.nf
.ft CR
.ps 8
CONFIG_LOCALVERSION="-lockdown-t14g3-audit6"
CONFIG_KVM_INTEL=y
CONFIG_INTEL_IOMMU=y
CONFIG_IRQ_REMAP=y
CONFIG_MT7921U=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_ETHERNET is not set
# CONFIG_SCSI_LOWLEVEL is not set
# CONFIG_MTD is not set
# CONFIG_XEN is not set
# CONFIG_HYPERV is not set
# CONFIG_KVM_AMD is not set
# CONFIG_VFIO_NOIOMMU is not set
.ps 10
.ft R
.fi
.SS Package and owner boundary
.PP
The audit6 bindeb-pkg build exited zero and produced the amd64 image package version 6.18.53-14, plus a separate libc headers package. The unsigned image package SHA-256 is 2979137ce15398e5ba2e2223909f86c00a4c310bbed245f3bcf1cd44415949f4. Its embedded config matches the audited snapshot byte-for-byte; the unsigned bzImage SHA-256 is 6b8d0e227ac97e0641187d74592f3511e6ca8aaeb55cdcaff663b27a914011cd. The build log records three frame-size warnings in unchanged maple_tree/WireGuard code, local single-label Debian email warnings, and linker .note.package metadata warnings. None stopped the build. Disabling DWARF avoided a separate multi-gigabyte debug package.
.PP
The unsigned package was extracted to a separate staging directory. sbverify printed No signature table present for its contained EFI image; its exit code alone was not used as proof of an existing signature. The image was signed with the existing external Paulino Power MOK private key and public certificate; neither key nor passphrase was copied into the repository. The image package's vmlinuz md5sums entry was updated from 44a8f592e519ab4c4c1569645a72103b to 2380e70f7a146ab0989281e6d4bfa05f and repacked with root ownership. A fresh extraction of the signed package passed all eight package md5sums, an exact embedded-config comparison, and sbverify against the MOK certificate. No loadable .ko files exist. The signed EFI image SHA-256 is c4d40be9304171363727f736270738ee164d3a1673eacbed535de67a69eebd60. The extracted config passed the project audit with zero failures, boot-critical 82/0/0, required preflight 83/0/0, and production security policy 26/0 again.
.PP
Installable signed image package: build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb, size 54495802 bytes, SHA-256 f4d8ad715fa4c247a07807c88d580e0d3a04b5bd9584a7a6633ec7e0cfab9ffa. This is a signed kernel image inside an ordinary Debian package, not a cryptographically signed .deb container. mokutil --test-key reports the MOK certificate already enrolled but exits nonzero with Failed to access kernel trusted keyring: Required key not available. This warning does not negate the successful static image signature check, nor does it prove the candidate will be accepted and booted at runtime.
.PP
No sudo installation or reboot was performed by Codex. The exact-release config/60-lockdown-audit6-firmware.conf drop-in is prepared for i915, MT7921U, SOF, and the signed regulatory database pair. Package success, image signature, installed image, generated initramfs, GRUB state, and successful boot are separate boundaries. The owner commands and preboot hold point are in docs/AUDIT6_OWNER_RUNBOOK.md. Inspect the generated initramfs and GRUB state before manually selecting the candidate; retain stock as default and audit3 as a custom rollback.
.PP
Fresh recovery inventory on 27 September: linux-image-7.0.0-34-generic version 7.0.0-34.34 is installed and both its /boot/vmlinuz and root-only initrd exist. The previously described known-good 7.0.0-31-generic package is now deinstalled with config files only; it is not a usable fallback entry. The live, booted audit3 package version 6.18.53-11 is installed with image and initrd. /etc/default/grub still says GRUB_DEFAULT=0, a visible menu and a 15-second timeout. Generated grub.cfg is root-readable and has not been re-inspected during this pass, so stock 34 as actual selected default and a successful stock 34 boot are not newly proven. Verify its menu entry during the owner preboot checks and boot stock 34 once before the audit6 trial if its bootability is not already established. Do not rely on stock 31 for recovery.
.nf
.ft CR
.ps 8
$ dpkg-deb -R build/audit6-final/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb \e
    build/audit6-final/sign-stage
$ sbverify --list build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
No signature table present
$ sbsign --key /home/the-ascended1/.sb-keys/MOK.priv \e
    --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    --output build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6.signed \e
    build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
$ sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6.signed
$ mv build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6.signed \e
    build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
$ md5sum build/audit6-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
2380e70f7a146ab0989281e6d4bfa05f  boot/vmlinuz-6.18.53-lockdown-t14g3-audit6
The DEBIAN/md5sums vmlinuz entry was replaced with the digest above.
$ dpkg-deb --build --root-owner-group build/audit6-final/sign-stage \e
    build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb
$ cd build/audit6-final/verify-stage && md5sum -c DEBIAN/md5sums
.ps 10
.ft R
.fi
.bp
.SH AUDIT6 CHECKSUM LOOKUP FOLLOW-UP, 28 SEPTEMBER 2026
.PP
The owner reported that sha256sum returned No such file or directory for the relative path build/audit6-final/signed/linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb. The pasted command displayed backslash-escaped underscores. This is an owner-reported lookup failure, not evidence of a missing signed package or a failed checksum comparison. A single unquoted backslash before an underscore is removed by Bash; the pasted spelling alone does not explain the failure. A different working directory or literal backslashes in the argument remain possible, but the exact cause was not established.
.PP
Read-only verification on the then-running audit3 host found the signed package at the project path, size 54495802 bytes, with the expected SHA-256. The following commands were run from the signed-package directory; the owner runbook now uses an absolute quoted path, without backslashes before underscores, to avoid working-directory ambiguity. At this lookup, installation and preboot inspection were still pending; the later installation and boot are recorded below.
.nf
.ft CR
.ps 8
$ cd /home/the-ascended1/Lock_Down/build/audit6-final/signed
$ pwd
/home/the-ascended1/Lock_Down/build/audit6-final/signed
$ ls -l -- linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb
$ sha256sum -- linux-image-6.18.53-lockdown-t14g3-audit6_6.18.53-14_amd64.deb | cut -c1-64
f4d8ad715fa4c247a07807c88d580e0d3a04b5bd9584a7a6633ec7e0cfab9ffa
.ps 10
.ft R
.fi
.bp
.SH AUDIT6 FIRST RUNTIME BOOT, 28 SEPTEMBER 2026
.PP
Audit6 was booted. The live kernel reports 6.18.53-lockdown-t14g3-audit6, boot ID b9c5217f-03c3-47d6-b2b9-f1463d796984; its kernel journal begins at 01:59:57 EDT. The signed image package version 6.18.53-14 is installed. The installed image verifies against the existing MOK certificate, and the installed config matches the reviewed audit6 config. Its SHA-256 is recorded in the command excerpt below. The first boot reached userspace and mounted ext4 root on ubuntu-vg/ubuntu-lv through dm_crypt-0 and the LUKS partition. Active /swap.img remains on that encrypted root path. No swap migration was performed.
.PP
Secure Boot reports enabled; securityfs reports integrity lockdown. The journal reports Secure boot enabled, Kernel is locked down from Kernel configuration, Intel IOMMU translated domain, IRQ remapping enabled, and TPM 2.0 detected. All 12 CPUs are online and systemctl --failed lists zero units. Snap squashfs mounts are present. i915 bound the integrated display and loaded DMC, GuC, and HuC firmware; the external MT7921U loaded firmware and NetworkManager reports its Wi-Fi interface connected. The HDA/Realtek audio device and ALSA nodes are present. /dev/kvm is accessible to the owner account; a diskless QEMU machine initialized KVM, reported kvm support: enabled, and exited zero. This demonstrates KVM host initialization but not an actual guest workload.
.PP
The audit6 initramfs listing supplied by the owner contains Intel microcode, crypt/LVM/rootfs-block components, the correct rd.luks.uuid for 6dc6712f-ec48-4782-a37a-9cef06b82a0d, the matching etc/crypttab mapping, i915/MT7921U/SOF firmware, and regulatory.db plus regulatory.db.p7s. The current kernel journal has no match for the prior regulatory.db load failure, NETtel, nandsim, or IEEE802154 fakelb encryption-failed message. The separate MAC80211_HWSIM driver still initializes and creates wlan0, wlan1, and hwsim0. Numerous other unused built-in drivers still probe and warn, notably watchdog, old network, display-test, sensor, and non-Lenovo platform paths. Audit6 is a working checkpoint, not a minimal or warning-free kernel.
.PP
The owner reports keyboard, TrackPoint, touchpad, brightness, speaker playback, microphone response in the GNOME input meter, a direct USB-C external display, USB storage, and HDMI passing on audit6. PipeWire exposes the Realtek ALC257 built-in microphone source at full volume. Suspend/resume and a real KVM guest were not reported tested. The headphone jack is explicitly outside the owner's required checklist and has not been tested. The owner states Ethernet is disabled in BIOS and is not a required active path. The Thunderbolt NHI PCI functions at 00:0d.2 and 00:0d.3 remain enumerated without a bound kernel driver; firmware ThunderboltAccess was reported Disable. This does not establish pre-boot PCIe tunneling policy. The installed audit3 image and initramfs remain available as the demonstrated custom rollback. Stock 7.0.0-34-generic is installed with image and initramfs and remains GRUB_DEFAULT=0, but no successful stock 34 runtime boot has been observed.
.nf
.ft CR
.ps 8
$ uname -r
6.18.53-lockdown-t14g3-audit6
$ cat /proc/sys/kernel/random/boot_id
b9c5217f-03c3-47d6-b2b9-f1463d796984
$ sha256sum /boot/config-6.18.53-lockdown-t14g3-audit6 | cut -c1-64
88fab201f7a95a00e70f80d3ddfaa98e3cfbb6bde0826c75b4aee029940a7cb1
$ findmnt -no SOURCE,FSTYPE /
/dev/mapper/ubuntu--vg-ubuntu--lv ext4
$ cat /sys/kernel/security/lockdown
none [integrity] confidentiality
$ mokutil --sb-state
SecureBoot enabled
$ nproc
12
$ systemctl --failed --no-pager
0 loaded units listed.
$ nmcli -t -f DEVICE,TYPE,STATE device status
wlxe84e06b03f86:wifi:connected
$ printf \(aqinfo kvm\enquit\en\(aq |
    qemu-system-x86_64 -machine none,accel=kvm -nodefaults -nographic -S -monitor stdio
kvm support: enabled
.ps 10
.ft R
.fi
.SH AUDIT7 REQUESTED NARROW REDUCTION, 28 SEPTEMBER 2026
.SS Scope and provenance
.PP
The owner requested four further reductions while keeping Intel KVM: all AMD audio paths, the mac80211 simulated-radio test driver, i915 GVT-g KVM GPU sharing, and Xen guest emulation in KVM. Audit7 starts from the complete installed and booted audit6 resolved config, not a loaded-module inventory. The audit6 config snapshot and /boot/config match at SHA-256 88fab201f7a95a00e70f80d3ddfaa98e3cfbb6bde0826c75b4aee029940a7cb1. The pinned Linux 6.18.53 tar.xz SHA-256 is 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0. Its detached uncompressed-tar signature again verified with Greg Kroah-Hartman's kernel.org-published 647F28654894E3BD457199BE38DBBDC86092693E key before fresh extraction into build/audit7-final. GPG reports the local key is not personally certified; the published fingerprint is the signer-identity basis.
.SS Resolved config and static gates
.PP
The release identity is 6.18.53-lockdown-t14g3-audit7. The fragment disables CONFIG_MAC80211_HWSIM, CONFIG_DRM_I915_GVT_KVMGT, CONFIG_KVM_XEN, and independent AMD SOF, ACP, and SoundWire audio parent switches. The initial four-switch config still had 34 AMD ACP/SoundWire audio built-ins. Its build was intentionally stopped before package creation; the partial log is retained as build-attempt1-stopped.log. The fragment was expanded to satisfy the owner's full AMD-audio exclusion and Kconfig resolution was repeated before restarting the build. olddefconfig and listnewconfig returned no new prompts. The final resolved config snapshot is config/candidate-6.18.53-lockdown-t14g3-audit7.config, SHA-256 34c21aa256ba500b7ea4058830492b5129e22ec9570a27d95a7c90fa500cb6bd. It has 8117 built-in =y selections versus 8173 in audit6, a reduction of 56. No AMD ACP, AMD SOF, or AMD SoundWire audio symbols remain enabled. The full diff includes Kconfig-dependent removals such as GVT, VFIO mediated-device, external KVM write tracking, AMD machine drivers, and one AMD-selected generic codec. Intel KVM, KVM Hyper-V paravirtual guest support, Intel SOF/HDA, i915 display, MT7921U, Type-C DisplayPort, NVMe and dm-crypt remain built in.
.PP
The required-symbol preflight passed 83/0/0, boot-critical validation passed 82/0/0, production security policy passed 26 checks, and the project config audit reported zero required failures. The first direct invocation of scripts/preflight-security.sh failed with Permission denied because the existing file mode is 0664; invoking it with bash passed all checks. This was a host script execution-mode issue, not a resolved-config failure.
.SS Reproducible command excerpt and boundary
.nf
.ft CR
.ps 8
$ sha256sum linux-6.18.53.tar.xz
4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0
$ set -o pipefail
$ xz -cd linux-6.18.53.tar.xz | gpg \e
    --homedir build/audit5-verify-gnupg --batch \e
    --verify build/audit3-final2/linux-6.18.53.tar.sign -
$ mkdir -p build/audit7-final/linux-6.18.53
$ tar -xf linux-6.18.53.tar.xz \e
    -C build/audit7-final/linux-6.18.53 --strip-components=1
$ cp config/candidate-6.18.53-lockdown-t14g3-audit6.config \e
    build/audit7-final/linux-6.18.53/.config
$ KCONFIG_CONFIG="$PWD/build/audit7-final/linux-6.18.53/.config" \e
    bash build/audit7-final/linux-6.18.53/scripts/kconfig/merge_config.sh \e
    -m -Q build/audit7-final/linux-6.18.53/.config config/hardened.config
$ make -C build/audit7-final/linux-6.18.53 olddefconfig
$ make -C build/audit7-final/linux-6.18.53 listnewconfig
$ bash scripts/preflight-security.sh build/audit7-final/linux-6.18.53/.config
OK: production security-policy gate passed (26 checks).
$ make -C build/audit7-final/linux-6.18.53 -j12 bindeb-pkg \e
    KDEB_PKGVERSION=6.18.53-15
.ps 10
.ft R
.fi
.PP
The corrected audit7 bindeb-pkg build exited zero and produced the amd64 image package version 6.18.53-15 plus libc headers. The unsigned image package SHA-256 is 4e4e7cb28e6c92101d35d1695b36b21816803ee67be5beb5d284d9cf0be00d0f; its unsigned bzImage SHA-256 is 166ceed7fe87b02488425ab2b67fd755fb4e9f64b20a4c2bf834e77845b4af54. The embedded config matches the final audit7 snapshot byte-for-byte, and the package has no loadable .ko files. The build log contains nonfatal single-label Debian email, two unchanged WireGuard frame-size, and discarded .note.package metadata warnings. No compiler or package error occurred.
.PP
The unsigned package was extracted into a separate sign stage. Its EFI image reported No signature table present. The image was signed with the existing external Paulino Power MOK private key and matching public certificate; the private key was not printed or copied into the repository. sbverify against the public certificate reported Signature verification OK. The signed EFI image SHA-256 is 5804746a4a6ab704df156c2784f825e6d345ae6221b5de71cc8cc1295dceaeb0. The package's vmlinuz md5sums entry was updated, and it was repacked with root ownership. A fresh extraction of the final signed package passed all eight payload md5sums, exact config comparison, sbverify, and no-loadable-module inspection. Re-running the four static gates on the extracted config passed 83/0/0 required preflight, 26 security-policy checks, 82/0/0 boot-critical checks, and zero required project-audit failures.
.PP
Installable signed image package: build/audit7-final/signed/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb, size 54217162 bytes, SHA-256 e524b0e621c0a3cd80ace944352dec04db6050e451ee6e8d07438bfc9c4ffdce. This is a signed EFI kernel image inside an ordinary Debian package, not a cryptographically signed .deb container. The exact-release dracut drop-in is config/60-lockdown-audit7-firmware.conf, retaining the early firmware set used by working audit6. The owner commands and preboot hold point are in docs/AUDIT7_OWNER_RUNBOOK.md.
.nf
.ft CR
.ps 8
$ dpkg-deb -f build/audit7-final/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb \e
    Package Version Architecture
Package: linux-image-6.18.53-lockdown-t14g3-audit7
Version: 6.18.53-15
Architecture: amd64
$ sbsign --key /home/the-ascended1/.sb-keys/MOK.priv \e
    --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    --output build/audit7-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit7.signed \e
    build/audit7-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit7
$ sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    build/audit7-final/verify-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit7
Signature verification OK
$ sha256sum build/audit7-final/signed/linux-image-6.18.53-lockdown-t14g3-audit7_6.18.53-15_amd64.deb
e524b0e621c0a3cd80ace944352dec04db6050e451ee6e8d07438bfc9c4ffdce
.ps 10
.ft R
.fi
.PP
At the original audit7 package handoff, it was not installed or booted. The later installation and supervised boot are recorded below; this earlier boundary must not be read as the current state.
.SH AUDIT7 FIRST RUNTIME BOOT, 28 SEPTEMBER 2026
.PP
The owner installed the signed audit7 package after staging its exact-release dracut firmware drop-in. The owner-supplied preboot listing showed Intel microcode, crypt/LVM/rootfs-block and crypttab entries, the matching LUKS UUID 6dc6712f-ec48-4782-a37a-9cef06b82a0d and LVM root, i915 and MT7921U firmware, Intel SOF firmware/topologies, and regulatory.db with its p7s signature. GRUB listed matching audit7 kernel/initramfs entries alongside audit6, audit3, and stock 34. This was a static preboot check, not boot proof.
.PP
The live audit7 boot was then checked directly. It mounted /dev/mapper/ubuntu--vg-ubuntu--lv as ext4, reported 12 CPUs and zero failed systemd units, SecureBoot enabled and integrity lockdown, and a connected MT7921U Wi-Fi interface. /dev/kvm exists. The owner reported USB-C and HDMI displays, keyboard, USB storage, speakers, microphone, and trackpad working on audit7. The active /swap.img remains unchanged. A real KVM guest, s2idle suspend/resume, and a tested stock-34 default/fallback boot are not established by these observations.
.PP
Audit7 still enables the media test stack despite no camera or tuner in the observed PCI/USB inventory. Live sysfs exposes vivid and codec-test video, radio, and fake touch devices. Its boot journal also shows several built-in legacy watchdog probes competing for the legacy /dev/watchdog alias; iTCO_wdt nevertheless appears as watchdog1, with intel_oc_wdt and Software Watchdog as watchdog2 and watchdog3. The alias warning is not proof that iTCO_wdt is absent. These are separate future pruning candidates.
.nf
.ft CR
.ps 8
$ uname -r
6.18.53-lockdown-t14g3-audit7
$ mokutil --sb-state
SecureBoot enabled
$ cat /sys/kernel/security/lockdown
none [integrity] confidentiality
$ findmnt -no SOURCE,FSTYPE /
/dev/mapper/ubuntu--vg-ubuntu--lv ext4
$ systemctl --failed
0 loaded units listed.
$ nmcli -t -f DEVICE,TYPE,STATE device status
wlxe84e06b03f86:wifi:connected
.ps 10
.ft R
.fi
.SH AUDIT8 MEDIA AND IR REDUCTION, 28 SEPTEMBER 2026
.SS Scope and observed cause
.PP
The owner confirmed that cameras, video capture, TV tuners, SDR, and IR remotes are outside this kernel's intended use. Audit7 has no observed PCI/USB capture device, yet its resolved config enables MEDIA_SUPPORT, RC_CORE, media test drivers, and 179 DVB-prefixed built-in options. The audit7 boot created vivid video/radio and fake touch nodes. This is an actual loaded test surface, not merely a file-size observation. Audit8 is an isolated media/IR reduction; watchdog, filesystem, audio, GPU, Wi-Fi, KVM, and storage changes are deferred.
.SS Test-first resolved config and trust boundary
.PP
The new tests/test-audit8-media-config.sh checks the effective config for removed media/IR support and retained HDMI CEC, display, real touchpad, audio, Wi-Fi, USB storage, NVMe, ext4, squashfs, dm-crypt, Intel KVM, and IOMMU. It was first run against audit7 and failed on the five intended media symbols. The fragment then requested MEDIA_SUPPORT=n and RC_CORE=n with a distinct audit8 local version. The complete booted audit7 config, not a loaded-module list, was used as the base for fresh Kconfig resolution. The 6.18.53 source tarball's SHA-256 again matched 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0, and its detached uncompressed-tar signature verified against Greg Kroah-Hartman's kernel.org-published 647F28654894E3BD457199BE38DBBDC86092693E fingerprint. GPG reports the local key is not personally certified; the published fingerprint is the signer-identity basis.
.PP
The resolved release is 6.18.53-lockdown-t14g3-audit8. Its config snapshot is config/candidate-6.18.53-lockdown-t14g3-audit8.config, SHA-256 f7a9ebd9d0fc799a4c59c327e768ee4dbe54c17856b299239128e89ea885f33b. Kconfig resolved 7496 built-in =y symbols versus 8117 for audit7: 621 prior =y symbols disappeared and none were added. That count includes dependencies and is not a count of vulnerable drivers or a measured security improvement. The media test gate passed; listnewconfig produced no prompts; boot-critical validation passed 82/0/0, the required-symbol preflight passed 83/0/0, production security policy passed 26 checks, and the project config audit reported zero required failures. HDMI CEC core and notifier remained =y; the IR-remote core and capture subsystem resolved =n.
.nf
.ft CR
.ps 8
$ bash tests/test-audit8-media-config.sh \e
    config/candidate-6.18.53-lockdown-t14g3-audit7.config
FAIL CONFIG_MEDIA_SUPPORT expected=n actual=y
FAIL CONFIG_RC_CORE expected=n actual=y
FAIL CONFIG_MEDIA_TEST_SUPPORT expected=absent actual=y
FAIL CONFIG_VIDEO_VIVID expected=absent actual=y
FAIL CONFIG_DVB_CORE expected=absent actual=y
$ KCONFIG_CONFIG="$PWD/build/audit8-final/linux-6.18.53/.config" \e
    bash build/audit8-final/linux-6.18.53/scripts/kconfig/merge_config.sh \e
    -m -Q build/audit8-final/linux-6.18.53/.config config/hardened.config
$ make -C build/audit8-final/linux-6.18.53 olddefconfig
$ make -C build/audit8-final/linux-6.18.53 listnewconfig
$ bash tests/test-audit8-media-config.sh \e
    build/audit8-final/linux-6.18.53/.config
audit8 media config gate: PASS
$ sha256sum config/candidate-6.18.53-lockdown-t14g3-audit8.config
f7a9ebd9d0fc799a4c59c327e768ee4dbe54c17856b299239128e89ea885f33b
.ps 10
.ft R
.fi
.SS Built package, MOK signature, and owner boundary
.PP
The fresh-source bindeb-pkg build exited zero and produced the amd64 image package version 6.18.53-16 plus libc headers. The unsigned image package SHA-256 is 8b3267bc111222182c8c50ce7cc6c393b4b3cdd0a30a9733315ae0132ea65a2b. The build log contains nonfatal single-label Debian email, maple_tree and WireGuard frame-size, and discarded .note.package metadata warnings; no compiler or package error occurred. The unsigned package was extracted into a separate sign stage, whose image initially reported No signature table present. The existing external MOK key signed only the EFI kernel image; the private key was not printed or copied into the repository. The signed EFI image SHA-256 is 2e5464d26ede546ce30ef9e95370492da847028048c3e0f1de7c428cd861d054.
.PP
The image's md5sums entry was updated, the package was repacked with root ownership, and a fresh extraction of the final signed package passed all eight payload md5sums. Its embedded config matches the audit8 snapshot byte-for-byte, its EFI image verifies against the existing MOK public certificate, and it contains no loadable .ko files. The final media gate and security-policy gate passed on the extracted config. The exact-release dracut firmware drop-in is config/60-lockdown-audit8-firmware.conf and was syntax-checked against the retained audit7 firmware list. The installable signed image package is build/audit8-final/signed/linux-image-6.18.53-lockdown-t14g3-audit8_6.18.53-16_amd64.deb, size 50057330 bytes, SHA-256 f7c722e63ea6fd32fb5ee92964c4681a59e05bbd5eb12acf3528d7539d64ff77. The package contains a signed EFI image; the Debian package container is not cryptographically signed.
.nf
.ft CR
.ps 8
$ make -C build/audit8-final/linux-6.18.53 -j12 bindeb-pkg \e
    KDEB_PKGVERSION=6.18.53-16
$ dpkg-deb -R build/audit8-final/linux-image-6.18.53-lockdown-t14g3-audit8_6.18.53-16_amd64.deb \e
    build/audit8-final/sign-stage
$ sbverify --list build/audit8-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit8
No signature table present
$ sbsign --key /home/the-ascended1/.sb-keys/MOK.priv \e
    --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    --output build/audit8-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit8.signed \e
    build/audit8-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit8
$ sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    build/audit8-final/verify-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit8
Signature verification OK
$ sha256sum build/audit8-final/signed/linux-image-6.18.53-lockdown-t14g3-audit8_6.18.53-16_amd64.deb
f7c722e63ea6fd32fb5ee92964c4681a59e05bbd5eb12acf3528d7539d64ff77
.ps 10
.ft R
.fi
.PP
No audit8 package was installed, no audit8 initramfs or GRUB entry was generated, and audit8 has not booted. Audit7 and older recovery kernels remain unchanged; active swap is unchanged. The owner must compare the exact final package digest, install the audit8-only firmware drop-in before the signed package, inspect the generated initramfs and GRUB fallback entries, and then manually select audit8 for one supervised boot. The exact commands and hold points are in docs/AUDIT8_OWNER_RUNBOOK.md.
.SH AUDIT9 DEVICE AND PROTOCOL REDUCTION, 28 SEPTEMBER 2026
.SS Scope, hardware exceptions, and test-first config
.PP
The owner approved a staged series of reductions: audit9 removes unused device and protocol families; later candidates will review filesystems, lockdown-gated interfaces, and audio separately. The owner expressly kept Snap/SquashFS and crash diagnostics. Audit8 remains built and signed but uninstalled and unbooted, so audit9 is a static successor, not a validated runtime replacement. Neither audit8 nor any older package was changed.
.PP
The live audit7 inventory showed only xHCI USB host controllers and the 0e8d:7961 MT7921U adapter in use. The input inventory had no touchscreen, but udevadm traced the working SYNA8018:00 touchpad through hid-multitouch and i2c_hid_acpi. Thus audit9 disables CONFIG_INPUT_TOUCHSCREEN while deliberately retaining CONFIG_HID_MULTITOUCH=y. No IIO device appeared beyond the sysfs test trigger. The live active LSM list was lockdown, capability, Landlock, Yama, AppArmor, IMA, and EVM; SELinux, Smack, TOMOYO, IPE, and SafeSetID were compiled but not active.
.PP
The new tests/test-audit9-device-config.sh was first run against audit8 and failed on 34 requested family roots. The fragment requested their removal and a unique audit9 release. Kconfig initially kept USB_ACM=y because two unneeded external USB HDMI-CEC adapter drivers selected it; those drivers were disabled while CEC_CORE stayed enabled. Disabling the USB gadget menu also changed three unrelated dual-role controllers to host-only y, so their parent drivers were removed after confirming the live host binds xhci_hcd. A later diff found seven OVS, SCTP, L2TP, and MPLS helpers still enabled despite parent removal. The provisional compile was intentionally terminated with status 143 before packaging; the corrected fragment also disables the tc connection-tracking action that selected the remaining OVS helpers. The final resolver and test gate then passed. The in-tree EFI display, USB host/HID/storage, MT7921U, SOF/HDA, Intel KVM/IOMMU, ext4, SquashFS, AutoFS, FUSE, dm-crypt, KEXEC/CRASH_DUMP, X86_MSR, and active LSM paths remain gated as y.
.PP
The upstream tar SHA-256 again matched 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0 and its detached signature verified with the prior imported Greg Kroah-Hartman key fingerprint 647F28654894E3BD457199BE38DBBDC86092693E; GPG still reports undefined personal trust. Freshly extracted source was configured from the complete audit8 snapshot plus config/hardened.config and olddefconfig. No new Kconfig prompts appeared. The final resolved audit9 config snapshot SHA-256 is 65902ef6b23f494713d232820ad9c4285dcb6ed852d6d0aa41bd33bcdbad0d7e. It has 6248 =y symbols versus audit8's 7496: 1248 prior built-ins removed, zero newly enabled. This is a configuration count, not proof of runtime security or power gains. The audit9 device test passed; required preflight passed 83/0/0, boot-critical validation 82/0/0, production security policy 26 checks, and the project audit reported zero required failures.
.nf
.ft CR
.ps 8
$ udevadm info --attribute-walk --name=/dev/input/event12 | grep DRIVERS
DRIVERS=="hid-multitouch"
DRIVERS=="i2c_hid_acpi"
$ bash tests/test-audit9-device-config.sh \e
    config/candidate-6.18.53-lockdown-t14g3-audit8.config
audit9 device config gate: 34 failures
$ xz -dc linux-6.18.53.tar.xz | gpg \e
    --homedir build/audit5-verify-gnupg --verify \e
    build/audit3-final2/linux-6.18.53.tar.sign -
Good signature from Greg Kroah-Hartman; trust undefined
$ make -C build/audit9-final/linux-6.18.53 olddefconfig
$ bash tests/test-audit9-device-config.sh \e
    build/audit9-final/linux-6.18.53/.config
audit9 device config gate: PASS
$ sha256sum config/candidate-6.18.53-lockdown-t14g3-audit9.config
65902ef6b23f494713d232820ad9c4285dcb6ed852d6d0aa41bd33bcdbad0d7e
.ps 10
.ft R
.fi
.SS Final build, signed image package, and owner boundary
.PP
The corrected fresh-source bindeb-pkg build exited zero and produced version 6.18.53-17 amd64 image and libc-dev packages. The unsigned image package is 39716098 bytes with SHA-256 9a0cb10ae8726eeb2edf8946b9763c98b10ccbcae749d3fb08380e416d28e0df. The final build log has nonfatal WireGuard frame-size, discarded .note.package metadata, and single-label Debian maintainer-email warnings; it reported no compiler or package error. The unsigned package passed all eight payload md5sums, exact embedded-config comparison, and no-loadable-module inspection. Its EFI image had no signature table.
.PP
The external existing MOK key signed only the extracted EFI image; no private key was copied into the repository. The signed image SHA-256 is 897d69937808171f8f3b1dd13f0239630190b2ddaed801fdb67223070526b1b0. The image payload md5sums entry changed from 4d93969a1a45d4786821b37b11e80953 to 2434dfcd0d9a1077f452d23b4b48dc0f. The package was repacked with root ownership and freshly extracted. All eight final payload md5sums passed; the extracted EFI image verified against the MOK certificate; the embedded config matched the audit9 snapshot byte-for-byte; the audit9 device gate passed; and no .ko file was present. The exact-release dracut firmware drop-in config/60-lockdown-audit9-firmware.conf retained the audit8 firmware set, passed bash syntax checking, and all listed files were readable. It was not installed in /etc. The signed image package is build/audit9-final/signed/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb, 39718084 bytes, SHA-256 9d19f9937495ad975ca5859e38af6f35f69426a4eaea3717341f49dafaf9e5ea. The Debian package container itself is not cryptographically signed.
.nf
.ft CR
.ps 8
$ make -C build/audit9-final/linux-6.18.53 -j12 bindeb-pkg \e
    KDEB_PKGVERSION=6.18.53-17
$ dpkg-deb -R build/audit9-final/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb \e
    build/audit9-final/sign-stage
$ sbverify --list build/audit9-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9
No signature table present
$ sbsign --key /home/the-ascended1/.sb-keys/MOK.priv \e
    --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    --output build/audit9-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9.signed \e
    build/audit9-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9
$ mv -T build/audit9-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9.signed \e
    build/audit9-final/sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9
# DEBIAN/md5sums image line changed to 2434dfcd0d9a1077f452d23b4b48dc0f.
$ (cd build/audit9-final/sign-stage && md5sum -c DEBIAN/md5sums)
8 payload checks: OK
$ dpkg-deb --build --root-owner-group build/audit9-final/sign-stage \e
    build/audit9-final/signed/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb
$ sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    build/audit9-final/verify-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit9
Signature verification OK
$ sha256sum build/audit9-final/signed/linux-image-6.18.53-lockdown-t14g3-audit9_6.18.53-17_amd64.deb
9d19f9937495ad975ca5859e38af6f35f69426a4eaea3717341f49dafaf9e5ea
.ps 10
.ft R
.fi
.PP
At this 28 September build-stage hold point, audit9 and audit8 were not yet installed or booted. Both were subsequently installed. On 29 September, uname -r reported audit9, findmnt showed the mapper-backed ext4 root, and systemctl --failed reported zero failed units. The owner reported the audit9 keyboard, TrackPoint, touchpad, brightness, speakers, microphone, MT7921U Wi-Fi, USB storage, HDMI, and direct USB-C display working, and later confirmed the required physical hardware checklist passed. The diskless KVM smoke ran four guest initializations, but the owner has not yet completed KVM/VM testing; a real guest and suspend/resume remain separate checks. These later observations supersede the earlier installation hold without changing the recorded build history.
.SH AUDIT10 USB SPECIALTY-DRIVER REDUCTION, 29 SEPTEMBER 2026
.SS Scope and source-backed risk assessment
.PP
The owner approved a bounded audit10 cut of 28 built-in USB options from the running audit9 baseline: 13 specialty-device drivers, three host/compliance-test drivers, and 12 model-specific mass-storage bridge, card-reader, player, or button helpers. All 28 were =y in the exact installed audit9 config; the /boot, repository snapshot, and audit9 build-tree config hashes matched at 65902ef6b23f494713d232820ad9c4285dcb6ed852d6d0aa41bd33bcdbad0d7e. The specialty drivers are not all under drivers/usb/misc: MDC800 and MICROTEK are under drivers/usb/image, and SISUSBVGA has its own subdirectory. The live USB inventory on audit9 showed xHCI root hubs, virtual USB/IP VHCI root hubs, and the 0e8d:7961 MT7921U Wi-Fi adapter; no USB mass-storage device was attached during this audit.
.PP
The kernel USB core can match device-supplied IDs and call a matching driver's probe. Removing an unused built-in driver therefore removes its specific match/probe code path for a hot-plugged device. This is a plausible attack-surface reduction, not evidence that any one of the 28 drivers contains an exploitable flaw or merits a particular severity label. Generic USB mass storage, UAS, xHCI, HID, MT7921U, and SCSI disk support remain. The Cypress ATACB Kconfig help says its bridge still works with standard mass storage if the special helper is disabled, but loses ATA pass-through; other old bridges and card readers have no blanket fallback guarantee. Disabling SDDR09 also changes three generic usb-storage fallback quirks, so a count of 28 disabled symbols is not a full source-level behavior proof. USB/IP remains intentionally unchanged for a separate decision.
.SS Test-first configuration and static validation
.PP
tests/test-audit10-usb-config.sh first failed against audit9 with exactly 28 expected failures. The fragment then changed the release to audit10 and disabled those exact 28 options. The 6.18.53 tarball SHA-256 was 4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0; its detached uncompressed-tar signature verified with Greg Kroah-Hartman's kernel.org-published fingerprint 647F28654894E3BD457199BE38DBBDC86092693E in the previously imported local keyring. GPG still warns that personal trust in that key is undefined. Fresh source was extracted, seeded from the complete audit9 config, merged with config/hardened.config, and resolved by olddefconfig. listnewconfig produced no prompts. diffconfig showed exactly the local-version change and 28 y-to-n USB changes, with no other resolved Kconfig difference. The audit10 config snapshot SHA-256 is 121a6769868273d437d19d309a628793fabbec07f65e806568035740bd377f54; built-in =y symbols fell from 6248 to 6220. This count is not a measured security or power result.
.PP
The audit10 USB gate passed; prior audit8 media and audit9 device gates passed; required preflight passed 83/0/0; boot-critical validation passed 82/0/0; production security policy passed 26 checks; and the project config audit found zero required failures. BACKLIGHT_CLASS_DEVICE stayed =y despite disabling USB_APPLEDISPLAY. USBIP_CORE, USBIP_VHCI_HCD, and USBIP_HOST stayed =y as explicitly out of scope. The exact-release dracut drop-in retains audit9's 11 early-firmware items; bash syntax and item readability passed, and the drop-in does not activate for audit9.
.nf
.ft CR
.ps 8
$ bash tests/test-audit10-usb-config.sh \e
    /boot/config-6.18.53-lockdown-t14g3-audit9
audit10 USB config gate: 28 failures
$ xz -cd linux-6.18.53.tar.xz | gpg \e
    --homedir build/audit5-verify-gnupg --verify \e
    build/audit3-final2/linux-6.18.53.tar.sign -
Good signature from Greg Kroah-Hartman; personal trust undefined
$ make -C build/audit10-final/linux-6.18.53 olddefconfig
$ python3 build/audit10-final/linux-6.18.53/scripts/diffconfig \e
    config/candidate-6.18.53-lockdown-t14g3-audit9.config \e
    build/audit10-final/linux-6.18.53/.config
LOCALVERSION audit9 -> audit10; 28 USB symbols y -> n only
$ bash tests/test-audit10-usb-config.sh \e
    config/candidate-6.18.53-lockdown-t14g3-audit10.config
audit10 USB config gate: PASS
$ bash scripts/preflight-check.sh \e
    config/candidate-6.18.53-lockdown-t14g3-audit10.config \e
    config/required-symbols.txt
preflight: pass=83 fail=0 warn=0
.ps 10
.ft R
.fi
.SS Build, MOK signing, and the unbooted boundary
.PP
The first fresh-source build completed compilation and produced the bzImage, but its command session ended during Debian package staging before any .deb existed. No fatal compiler error appeared in that log. The incremental bindeb-pkg resume exited zero and produced the audit10 amd64 image and libc-dev packages at version 6.18.53-18. The unsigned image package is 39587228 bytes, SHA-256 a85e4d7b7cb1bd02bb8da87166911553ab01a4244b1e8f3de9820e0274cc05e3. Its embedded config matches the audited snapshot byte for byte; all eight unsigned payload MD5 checks passed; no .ko files are present; and sbverify reported no initial signature table. The build logs contain nonfatal maintainer-email single-label-domain, maple_tree and WireGuard frame-size, and linker .note.package warnings. No package-stage error remained after the successful resume.
.PP
The existing external MOK key signed only the extracted EFI image; no private key was copied into the repository. The signed image SHA-256 is 5deff16ca4d653a875aaa49a6f73db0de40ce37da6c7b4fb8c58cc3e778b1fe1. The image payload MD5 entry changed from 944aad55d0f215cdf2bd6b0e2d66ee4e to aa7aadc72adaab73c16a34ae23e6564d. After repacking with root ownership and extracting the final signed package into a separate verification stage, all eight payload MD5 checks, the embedded-config comparison, the audit10 USB gate, no-loadable-module check, and sbverify against the existing MOK certificate passed. The final signed image package, whose path appears in the command below and the owner runbook, is 39589142 bytes with SHA-256 8a98c461cdb4ba96e52b24ccb958100763ff2e7485cb3dcb9399fbecbff2ed44. The Debian package container itself is not cryptographically signed.
.nf
.ft CR
.ps 8
$ cd build/audit10-final
$ make -C linux-6.18.53 -j12 bindeb-pkg \e
    KDEB_PKGVERSION=6.18.53-18
# Initial session stopped after bzImage; incremental resume exited 0.
$ dpkg-deb -R \e
    linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb \e
    sign-stage
$ sbverify --list \e
    sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit10
No signature table present
$ sbsign --key /home/the-ascended1/.sb-keys/MOK.priv \e
    --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    --output sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit10.signed \e
    sign-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit10
# Replace staged image; update its one DEBIAN/md5sums entry.
$ (cd sign-stage && md5sum -c DEBIAN/md5sums)
8 payload checks: OK
$ dpkg-deb --build --root-owner-group sign-stage \e
    signed/linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb
$ sbverify --cert /home/the-ascended1/.sb-keys/MOK.pem \e
    verify-stage/boot/vmlinuz-6.18.53-lockdown-t14g3-audit10
Signature verification OK
$ sha256sum \e
    signed/linux-image-6.18.53-lockdown-t14g3-audit10_6.18.53-18_amd64.deb
8a98c461cdb4ba96e52b24ccb958100763ff2e7485cb3dcb9399fbecbff2ed44
.ps 10
.ft R
.fi
.PP
Audit10 has not been installed, has no generated /boot initramfs or GRUB entry, and has not booted. The running audit9 kernel remains untouched. docs/AUDIT10_OWNER_RUNBOOK.md provides the exact digest, owner-only sudo installation commands, preboot hold point, supervised manual GRUB selection, and postboot hardware/KVM checklist. No active swap, GRUB default, or previously installed kernel was changed.
.SH SECURITY AND POWER INTERPRETATION
.PP
The configuration changes have plausible mechanisms for improving idle behavior and reducing attack surface, but they are not battery-life measurements. Actual benefit must be demonstrated with repeated turbostat, wakeup, interrupt, package C-state, and discharge-rate measurements under identical userspace and firmware conditions.
.PP
The monolithic policy removes post-boot module loading attack surface and avoids a module-signing dependency, but it also prevents DKMS and other loadable-module workflows. A modular profile must be designed separately with signed modules and matching initramfs contents.
.SH INTENTIONALLY NOT CHANGED
.IP \(bu 2
No firmware Thunderbolt setting was changed. The custom-kernel USB4 option was excluded while the direct monitor paths were retained.
.IP \(bu 2
The owner installed the signed audit2 image package and changed GRUB timeout settings. No old kernel was deleted; candidate and stock entries were reported by update-grub. The candidate was booted once and failed functional validation; the stock kernel remains the recovery/default path.
.IP \(bu 2
No private keys were generated, enrolled, or modified, and no firmware Secure Boot state was changed. An enrolled public certificate was exported temporarily for verification.
.IP \(bu 2
No arbitrary governor, NVMe APST, USB autosuspend, or kernel command-line power tweak was applied.
.IP \(bu 2
No mitigation was disabled for benchmark performance.
.SH REMAINING WORK
.IP 1. 4
Audit9 is installed and currently booted. The owner confirmed the required physical hardware checks passed, including keyboard, TrackPoint, touchpad, brightness, speakers, microphone input-meter response, direct USB-C display, USB storage, and HDMI. Check s2idle suspend/resume and record failures or untested items. The headphone jack is excluded from the owner's requirements, and Ethernet is disabled in BIOS and outside the active-use checklist.
.IP 2. 4
Start a real KVM guest with the intended VM workflow. The diskless QEMU initialization passed, but it does not prove that a guest boots or remains usable.
.IP 3. 4
Keep audit3 installed as the observed working rollback and stock 34 as the configured default. Confirm a later normal reboot reaches the intended default. A stock 34 boot may be tested separately before relying on it for recovery; stock 31 is deinstalled.
.IP 4. 4
Audit8 is installed and was booted before audit9. Preserve it as an additional known bootable candidate; its media/capture and IR removals are no longer merely static. The owner reported its physical hardware tests passing, but the real-guest, suspend, and full fallback checks were not completed there.
.IP 5. 4
Audit9 is signed, installed, and booted; the owner reported the required physical hardware checklist passing. The owner has not yet completed KVM/VM testing; the deterministic diskless smoke is not accepted as full VM proof. Finish the real Ubuntu guest, guest-agent/network workflow, s2idle suspend/resume, and fallback/default checks before calling audit9 fully validated.
.IP 6. 4
Audit10 is built and MOK-signed but not installed or booted. Compare the exact signed-package SHA-256 8a98c461cdb4ba96e52b24ccb958100763ff2e7485cb3dcb9399fbecbff2ed44, then follow docs/AUDIT10_OWNER_RUNBOOK.md for owner-run installation, generated-initramfs and GRUB inspection, and a supervised manual boot. Recheck USB storage, Wi-Fi, display, input, audio, KVM, and suspend; no static gate establishes that result.
.IP 7. 4
The owner reported firmware ThunderboltAccess=Disable. Inspect firmware setup separately for any PCIe-tunneling control if a firmware-policy claim is required. NHI enumeration alone is not a firmware-policy answer. No setting was changed as part of this release.
.IP 8. 4
After audit10's own supervised test, review staged filesystem and lockdown/audio cuts separately. SquashFS, AutoFS, FUSE, kexec/crash dump, X86_MSR, KVM, external-display, firmware, removable-media, and recovery functions still require explicit keep/remove decisions. USB/IP and legacy watchdog contention remain separate candidates; neither is part of the audit10 cut.
.IP 9. 4
Only after functional and fallback validation, compare stock and custom kernels with repeated matched power measurements, then evaluate any additional hardening changes. Do not infer power or security improvements from the count of disabled Kconfig symbols.
.SH FILES
.IP \(bu 2
config/hardened.config
.IP \(bu 2
scripts/build-kernel.sh
.IP \(bu 2
preflight-check.sh
.IP \(bu 2
lock-down-kernel/scripts/audit-config.sh
.IP \(bu 2
lock-down-kernel/references/required-config.md
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit1.config
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit2.config
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit6.config
.IP \(bu 2
config/60-lockdown-audit6-firmware.conf
.IP \(bu 2
docs/AUDIT6_OWNER_RUNBOOK.md
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit7.config
.IP \(bu 2
config/60-lockdown-audit7-firmware.conf
.IP \(bu 2
docs/AUDIT7_OWNER_RUNBOOK.md
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit8.config
.IP \(bu 2
config/60-lockdown-audit8-firmware.conf
.IP \(bu 2
tests/test-audit8-media-config.sh
.IP \(bu 2
docs/AUDIT8_OWNER_RUNBOOK.md
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit9.config
.IP \(bu 2
config/60-lockdown-audit9-firmware.conf
.IP \(bu 2
tests/test-audit9-device-config.sh
.IP \(bu 2
docs/AUDIT9_OWNER_RUNBOOK.md
.IP \(bu 2
config/candidate-6.18.53-lockdown-t14g3-audit10.config
.IP \(bu 2
config/60-lockdown-audit10-firmware.conf
.IP \(bu 2
tests/test-audit10-usb-config.sh
.IP \(bu 2
docs/AUDIT10_OWNER_RUNBOOK.md
.IP \(bu 2
docs/THUNDERBOLT.md
.IP \(bu 2
docs/kernel-audit-change-log.ms
.SH END
This report documents repository changes and validation through 29 September 2026. Audit9 6.18.53-17 is currently running: uname -r confirms its release, the mapper-backed ext4 root is mounted, Secure Boot is enabled with integrity lockdown, and systemctl reports zero failed units. The owner reports the required physical hardware checklist passing, including keyboard, TrackPoint, touchpad, brightness, speaker playback, microphone, direct USB-C display, USB storage, HDMI, and MT7921U Wi-Fi. A fresh deterministic diskless KVM smoke passed four guest initializations, but the owner has not completed KVM/VM testing; a full libvirt guest and suspend/resume remain open. Audit8 and audit9 are installed; audit3, audit6, audit7, and stock Ubuntu 7.0.0-34 are also installed as fallback choices. Audit10 6.18.53-18 makes only the 28 approved USB exclusions plus a unique release identity, passed static configuration and package-signature gates, and is built and signed but neither installed nor booted. Stock 34 is installed and GRUB_DEFAULT=0 remains unchanged; a successful stock 34 boot and fallback behavior have not been reverified here. No power gain or exploit mitigation magnitude was measured. The headphone jack is out of scope, and swap is unchanged.
