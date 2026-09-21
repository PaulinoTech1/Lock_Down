# Kernel Version Policy

Project: hardware-tailored, security-first Linux workstation, Lenovo ThinkPad T14 Gen 3 Intel (21AJ), i5-1245U Alder Lake-U.

## Selected branch

**Upstream LTS 6.18** is the branch candidate for the custom hardened kernel.

Classification: RECOMMENDED. Confidence: Medium (branch choice is sound on paper; it is UNVERIFIED on this hardware until the first build boots and the test plan below passes).

Why 6.18:
- It is an LTS branch, so it receives stable backports for years rather than months, which reduces the rebase frequency compared to tracking a mainline stable branch.
- Its support horizon (see below) covers the expected useful life of this workstation project without forcing an early rebase.
- It postdates the 6.8 GA kernel shipped by Ubuntu 24.04, so Alder Lake-U, SOF audio, i915 Xe, NVMe APST, and VT-d/IOMMU support are all mature on this branch, and there is no need for out-of-tree backports for the hardware listed in the task brief.
- It is recent enough that modern hardening options (RANDOMIZE_KSTACK_OFFSET, landlock coverage, current LSM stack) are present in mainline form.

Alternatives considered and rejected:
- Ubuntu 24.04 stock kernel (6.8 GA) as the primary kernel: rejected as the daily driver because it carries the full distro driver set, which is exactly what this project trims. It is retained as the rescue kernel instead.
- Newest mainline stable (e.g. 7.2.x at time of writing): rejected because stable branches EOL within months and would force frequent rebases; the security benefit of newer code is outweighed by the maintenance risk on a single-maintainer project.

## Support horizon

6.18 LTS is listed by kernel.org as supported to **December 2027** (verified 2026-09-21 by parent).

**Re-verify at build time.** Support horizons are estimates and can be extended or cut short. Before every build, check the current LTS status at https://kernel.org and record the result in the build log. Do not treat Dec 2027 as a promise.

## Security patch tracking

The custom kernel is only as secure as its last stable update. Patch tracking is:

1. Subscribe to the stable release announcements (linux-stable mailing list / kernel.org releases) and check for a new 6.18.x point release at least weekly.
2. Track CVEs affecting the enabled subsystem set: kernel.org CVE feed plus the CISA KEV catalog for prioritization. A KEV-listed kernel CVE in an enabled subsystem triggers an out-of-band rebuild; anything else rides the next point release.
3. Keep the tracking log at `repo/docs/PATCH_TRACKING.md` (create at first build): release tag built, date checked, CVEs applied, test result. If the log goes quiet, the kernel is stale.

## Update test plan

Every point-release rebuild must pass this sequence before the new kernel becomes the default boot entry:

1. **Build**: `make` completes cleanly with the hardened config; no new warnings in enabled subsystems (warnings are reviewed, not waived).
2. **Boot hardened**: boot the new kernel; verify dmesg is free of subsystem failures (NVMe, i915, SOF, mt7921u, TPM, IOMMU groups sane).
3. **Boot diagnostic**: boot the diagnostic build; verify tracing tooling attaches (ftrace, perf, eBPF smoke test).
4. **Rescue fallback**: confirm the Ubuntu distro kernel entry still boots (boot it, or at minimum confirm the bootloader entry and initramfs are intact after each kernel install).
5. **Suspend/resume smoke**: one s2idle suspend/resume cycle, confirm Wi-Fi (mt7921u) and audio re-attach.

If any step fails, the previous working custom kernel stays default and the failure is recorded. The distro rescue kernel is never removed, period.

## When rebasing to a new LTS is justified

Rebase only when one of these is true:

- The 6.18 LTS branch reaches end of life (confirmed on kernel.org, not rumored).
- A security fix for an enabled subsystem is only available on a newer branch and cannot be cleanly backported.
- A hardware-enabling need appears that 6.18 cannot satisfy (unlikely for this fixed hardware set).
- Ubuntu 24.04 HWE or 26.04 LTS changes make alignment with a newer LTS cheaper than staying (evaluated, not assumed).

Rebasing "because a newer LTS exists" is not a justification. Each rebase re-runs the full validation: config diff review, hardened boot, diagnostic boot, rescue check, suspend smoke.

## CVE response handling

- Severity and exploitability are judged against the enabled config, not the kernel in the abstract. A CVE in amdgpu is irrelevant here because amdgpu is not built. A CVE in i915, KVM, or the USB Wi-Fi stack is urgent.
- KEV-listed kernel CVE in an enabled subsystem: rebuild within days, test, deploy. Classification: highest priority.
- Stable point release with security fixes: rebuild on the next scheduled cycle, test, deploy.
- CVE in a disabled subsystem: log it, no action. This is one of the concrete payoffs of the reduced config: a smaller attack surface means a smaller patch-triage queue.
- If a rebuild cannot be completed promptly (travel, breakage), fall back to booting the distro kernel, which receives Canonical's security updates, until the custom kernel is current again.

## Distro rescue kernel retention

- The Ubuntu 24.04 kernel is ALWAYS retained and is a permanent bootloader entry. It is the recovery path if the custom kernel fails to boot, misbehaves after an update, or is found to be stale.
- No script, hook, or package operation in this project may remove the distro kernel or old working custom kernels. `build-kernel.sh` refuses to remove existing kernels (see repo/scripts/build-kernel.sh).
- Disk space pressure is not a reason to delete the rescue kernel. If /boot fills up, remove nothing automatically; alert and handle manually.

## The core acknowledgment

**An unpatched custom kernel is worse than the distro kernel.** Canonical ships tested security updates for 24.04 on a schedule; this project has one maintainer. The moment patch tracking lapses, the "hardened" kernel becomes the least secure kernel on the machine because it carries the illusion of hardening without the updates that make it real. If maintenance cannot be sustained, the correct action is to stop building custom kernels and run the distro kernel with the hardening that lives outside the kernel (AppArmor profiles, nftables, LUKS2, Secure Boot) until maintenance resumes. This is stated plainly so it is never rationalized away.
