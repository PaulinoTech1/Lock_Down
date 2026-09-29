---
name: lock-down-kernel
description: Audit, troubleshoot, build, and benchmark this hardware-specific Linux kernel for the Lenovo ThinkPad T14 Gen 3 Intel, with measured power efficiency and security hardening.
metadata:
  short-description: Audit and improve the Lock_Down custom kernel
---

# Lock Down Kernel Skill

Use this skill for work in the Lock_Down repository involving the custom Linux
kernel, its Kconfig fragments, build/signing workflow, boot chain, hardware
support, security posture, or power measurements.

## Scope and operating rules

- This is a deliberately narrow kernel for one Lenovo ThinkPad T14 Gen 3 Intel
  (21AJ), Core i5-1245U Alder Lake-U. Do not apply generic distribution-kernel
  advice without reconciling it with the project hardware and threat model.
- Treat the effective `.config` after Kconfig dependency resolution as the
  authority. Fragments, documentation, and comments are intent, not proof.
- Start audits read-only. Before changing configuration, boot files, signing
  material, or installation behavior, report the finding, likely cause, risk,
  and proposed change. Do not install or delete kernels unless the user
  explicitly asks for that operation.
- Preserve a known-good Ubuntu kernel and a documented recovery path. Never
  make an experimental kernel the only bootable entry.
- Separate CONFIRMED facts, HIGH-CONFIDENCE INFERENCES, and HYPOTHESES. A
  power claim requires before/after measurements with the same userspace and
  hardware state.
- Do not use `localmodconfig` as the sole minimization method. It only records
  devices exercised during collection and can remove suspend, rescue, firmware,
  alternate network, audio, USB-C, TPM, or initramfs functionality that was
  idle during the collection window.
- Do not treat a smaller image as a battery-life result. Prioritize runtime
  wakeups, idle residency, runtime PM, PCIe ASPM, NVMe APST, graphics power,
  and userspace ownership of power policy.
- Keep Secure Boot, kernel signing, module signing, lockdown, IOMMU, AppArmor,
  namespaces, BPF, io_uring, and KVM decisions explicit. Do not weaken a
  meaningful mitigation for an unmeasured benchmark gain.

## Workflow

1. Establish the project root, current branch, effective kernel version, source
   tree, output directory, configuration provenance, and installed fallback.
2. Read [hardware-inventory.md](references/hardware-inventory.md) and the
   relevant sections of [required-config.md](references/required-config.md) and
   [forbidden-config.md](references/forbidden-config.md).
3. Run `scripts/audit-config.sh` and `scripts/validate-boot-critical.sh` on the
   effective configuration. Use `scripts/diff-config.sh` for baseline/candidate
   comparisons.
4. For power work, read [benchmark-protocol.md](references/benchmark-protocol.md)
   and run `scripts/collect-power-data.sh`. Do not change governors, autosuspend,
   APST, or kernel command-line parameters during a baseline measurement.
5. For boot and signing work, read [boot-chain.md](references/boot-chain.md).
   Verify the trust chain and recovery path before recommending installation.
6. Make small, logically separate changes only after the initial findings are
   presented or the user explicitly requests implementation. Re-run Kconfig
   resolution, validation, relevant tests, and a build check after changes.

## Project-specific references

- Hardware facts and unresolved evidence: [hardware-inventory.md](references/hardware-inventory.md)
- Required effective symbols and dependency principles: [required-config.md](references/required-config.md)
- Production exclusions and unsafe shortcuts: [forbidden-config.md](references/forbidden-config.md)
- UEFI, Secure Boot, signing, initramfs, and recovery: [boot-chain.md](references/boot-chain.md)
- Repeatable baseline/candidate measurements: [benchmark-protocol.md](references/benchmark-protocol.md)

## Helper scripts

All bundled scripts are read-only with respect to the kernel and boot system.
They may write reports to an explicitly selected output directory.

```text
scripts/audit-config.sh [--project-root DIR] [--config FILE]
scripts/diff-config.sh BASE_CONFIG CANDIDATE_CONFIG
scripts/validate-boot-critical.sh CONFIG [SYMBOLS_FILE]
scripts/collect-power-data.sh [--output DIR] [--duration SECONDS] [--turbostat]
```

The scripts report missing tools or unavailable runtime state as UNKNOWN/WARN;
they must not silently convert unavailable evidence into a passing result.
