# CPU Security

Target: Intel Core i5-1245U (Alder Lake-U, 2P+8E), ThinkPad T14 Gen 3.

## Observed mitigation state (2026-09-21)

The following was OBSERVED under the then-running kernel on 2026-09-21. It
is a snapshot, not a guarantee: a kernel upgrade, microcode change, or
command-line change can alter it. Re-run `scripts/cpu-security-report.sh`
after any kernel or microcode change and compare.

- Microcode revision: 0x43b (observed 2026-09-21).
- Mostly "Not affected": GDS, meltdown, MDS, L1TF, MMIO, SRBDS, TAA, and
  related entries read "Not affected" under the running kernel.
- Active mitigations observed:
  - RFS "Clear Register File" (Register File Data Sampling mitigation).
  - SSB disabled via prctl (Speculative Store Bypass).
  - spectre_v1: usercopy and swapgs barriers.
  - spectre_v2: Enhanced / Automatic IBRS with conditional IBPB and
    BHI_DIS_S (Branch History Injection disabled).
  - vmscape: IBPB on VM exit.
- Confidence: High that this was the observed state on that date; Low that
  it persists without re-verification. The report script exists precisely
  because this state drifts.

## Kernel command-line policy (RECOMMENDED)

```text
mitigations=auto
```

- Purpose: keep the kernel's default mitigation selection, which tracks
  the CPU's actual vulnerability state and the loaded microcode. On this
  CPU the observed result is the set above.
- Why not `mitigations=off`: that would disable the active mitigations
  (IBRS/IBPB handling, SSB prctl/seccomp behavior, RFS clearing) for a
  performance gain that is not justified on a security-first workstation.
  Cost of `auto`: the small residual overhead of the active mitigations;
  negligible on this workload.
- Limitation: `mitigations=auto` does not cover SMT policy (below) and
  does not invent mitigations for hardware the kernel considers not
  affected. It is a selector, not a guarantee.
- Recovery path: if a workload regresses, measure first
  (`cpu-security-report.sh` before/after), then consider targeted
  `spectre_v2=` or `spec_store_bypass_disable=` adjustments instead of
  blanket `mitigations=off`.

## SMT policy

Default: do NOT disable SMT. (RECOMMENDED)

- Rationale: on this CPU only the 2 P-cores have SMT (2 threads each); the
  8 E-cores are single-threaded. The observed mitigation state already
  handles the in-scope speculative-execution issues with SMT on, and
  disabling SMT costs 2 threads (about 17% of logical CPUs) on a 15 W
  laptop where every thread counts for build and VM work.
- OPTIONAL exception: disable SMT while running hostile VMs
  (untrusted-analysis profile). Purpose: narrows cross-thread speculation
  channels (port contention, shared execution resources) between a hostile
  guest's vCPUs and host threads. Cost: lose the 2 P-core threads for the
  session; some single-threaded burst performance drops. Limitation: this
  narrows one channel class; it does not close cache-timing or other
  microarchitectural channels, and it does nothing about VM escape.
  How: boot with `mitigations=auto,nosmt` or `nosmt=force` for the session,
  then reboot without it. Never presented as a default.
- What SMT-off does NOT do: it does not make an untrusted guest safe, and
  it does not replace KSM-off, sVirt, or VT-d. It is one optional layer.

## Microcode

- Purpose: microcode 0x43b (observed) carries the hardware assists the
  kernel mitigations rely on (e.g., Enhanced IBRS behavior).
- Keep microcode loading via early initramfs update
  (`MICROCODE_INTEL`, `intel-ucode` / distro microcode package). A kernel
  mitigation that depends on a microcode assist silently degrades if the
  microcode is stale; verify with the report script after updates.
- Cost: none beyond the distro package. Limitation: microcode cannot fix
  hardware that is vulnerable by design; it only enables the assists.
- Recovery path: if a microcode update regresses stability, the distro
  package can be held at the previous version while the regression is
  investigated; record the pinned version.

## Reporting

`scripts/cpu-security-report.sh` renders `/sys/devices/system/cpu/vulnerabilities/*`
as a plain-text report plus the microcode revision. It is read-only and
prints `UNKNOWN` for any entry it cannot read, so the report degrades
gracefully on kernels without the sysfs interface. Run it after every
kernel or microcode change and diff against the 2026-09-21 baseline above.
