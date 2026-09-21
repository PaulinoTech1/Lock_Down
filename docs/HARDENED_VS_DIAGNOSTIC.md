# Hardened vs Diagnostic Kernel: Complete Difference List

Both builds come from the same 6.18 LTS source tree, the same base driver set, and the same hardening posture. The diagnostic build is NOT a debug-everything build and NOT an unhardened build. It is the hardened build with observability re-enabled where observability conflicts with hardening.

Both builds are module-signed with the project key. The diagnostic build stays signed and Secure Boot trusted: diagnostics must never become an excuse to boot an unsigned kernel. Classification of this document: VERIFIED design intent; the exact Kconfig deltas live in repo/config/diagnostic.config.

## Governing principle

Observability costs attack surface. The hardened build pays as little as possible. The diagnostic build pays for exactly the tools needed to investigate a real problem on this hardware (i915 behavior, SOF audio, mt7921u Wi-Fi, suspend/resume, IOMMU, KVM), and nothing else. When the investigation ends, the machine goes back to the hardened build.

## Complete difference list

### 1. Kernel tracing (ftrace)

- Hardened: function tracing infrastructure minimized. `FUNCTION_TRACER` off, `FUNCTION_GRAPH_TRACER` off. Static tracepoints stay (they are cheap and some subsystems need them), but the dynamic function-tracing machinery is out.
- Diagnostic: `FUNCTION_TRACER=y`, `FUNCTION_GRAPH_TRACER=y`, `STACK_TRACER` enabled. This is the primary tool for "which function is hanging in suspend" or "what is i915 doing during this modeset".
- Rationale: function tracing lets any privileged user hook arbitrary kernel functions at runtime. In production that is unnecessary attack surface; during diagnosis it is the single most useful tool. KASAN is still out (see below); ftrace does not carry KASAN-class costs.

### 2. kprobes / kretprobes / uprobes

- Hardened: `KPROBES` off. No dynamic probing of kernel functions.
- Diagnostic: `KPROBES=y`, `KRETPROBES=y`, `UPROBES=y`. Needed for targeted probes (e.g. probe iwl-free suspend path functions, though iwlwifi is not built; probe mt7921u USB paths, nvme APST transitions).
- Rationale: kprobes are arbitrary-code-execution-adjacent by design (a probe handler runs in kernel context). Production does not need them; diagnosis of driver hangs sometimes does. Note: under lockdown=integrity, kprobes on certain paths are restricted; the diagnostic doc notes where lockdown may need to stay at integrity and where a probe simply will not attach, rather than weakening lockdown.

### 3. eBPF debugging and unprivileged eBPF

- Hardened: eBPF core stays (the report is explicit: never remove the eBPF core). `BPF_SYSCALL` on, but unprivileged eBPF off (unprivileged_bpf_disabled=2 at boot, i.e. fully disabled for unprivileged users). JIT on for the privileged paths that need it.
- Diagnostic: same core settings, but `BPF_JIT` debugging aids on (`BPF_JIT_DISASM` available) so eBPF programs used in diagnosis can be disassembled and verified. Unprivileged eBPF stays disabled in both builds; diagnostics are a root activity on this single-user machine.
- Rationale: eBPF is load-bearing for modern tooling (and for some security tooling later), so the core stays. The diagnostic delta is only the JIT introspection needed to debug eBPF-based diagnosis itself.

### 4. perf

- Hardened: `PERF_EVENTS` on (basic perf stat/top for the owner), but kernel-address exposure restricted: `perf_event_paranoid=3` at boot and `kptr_restrict=2`, so unprivileged users get no kernel samples and no kernel pointers.
- Diagnostic: same kernel options; boot-time sysctls relaxed to `perf_event_paranoid=1` and `kptr_restrict=0` for the diagnostic session only, so full kernel profiling and symbol resolution work. These are runtime settings, not config differences, and they revert on reboot into the hardened kernel.
- Rationale: perf is how you find the INIT_ON_FREE cost or a scheduler anomaly on Alder Lake's P/E topology. The kernel keeps the capability; the paranoid level is a per-boot policy choice.

### 5. debugfs exposure

- Hardened: debugfs is not mounted by default (fstab/systemd does not mount it); kernel built with `DEBUG_FS` allowed but unmounted. Sensitive entries (i915 error state, etc.) are not reachable without an explicit mount.
- Diagnostic: debugfs mounted during the session. Additionally `DEBUG_FS` stays enabled in both builds because several drivers (i915 included) expose their only detailed error dumps there.
- Rationale: debugfs is a large, historically buggy surface of raw kernel state. Unmounted in production, mounted only while diagnosing. This is a mount-policy difference, documented here because it is a real security boundary.

### 6. BTF (BPF Type Format)

- Hardened: `DEBUG_INFO_BTF` off. No BTF data shipped.
- Diagnostic: `DEBUG_INFO_BTF=y` (with `PAHOLE` available at build). BTF enables CO-RE eBPF tools (the modern bcc/bpftrace equivalents) to run against this exact kernel without headers.
- Rationale: BTF meaningfully improves eBPF-based diagnosis and costs only build time and image size. It is omitted from production because it aids anyone writing eBPF against the kernel, and production does not run eBPF diagnostics. Build cost note: BTF requires pahole; build-kernel.sh checks for it.

### 7. KASAN / KCSAN

- Both builds: EXCLUDED.
- Rationale: KASAN (address sanitizer) roughly doubles memory use and imposes severe performance costs; KCSAN (concurrency sanitizer) is similarly expensive and extremely noisy on a real workload. They are for catching bugs during development of new code, not for running a workstation. This project does not develop in-kernel code; it configures mainline. If a suspected memory-safety bug in an enabled driver ever needs KASAN, that is a one-off instrumented build, never a shipped config. This exclusion is deliberate and permanent for both profiles.

### 8. UBSAN

- Hardened: off.
- Diagnostic: off by default; may be enabled in a one-off build for a specific investigation. Not part of the standard diagnostic config because UBSAN slows the paths it instruments and has historically produced noise on driver code.
- Rationale: same class as KASAN but cheaper; still not worth it as a standing option.

### 9. Magic SysRq

- Hardened: SysRq restricted (`kernel.sysrq=4`, log-only style) or minimal; full SysRq (including process dumps and memory access) is not available to a local attacker at the console.
- Diagnostic: `kernel.sysrq=1` permitted during the session for crash investigation (sync, remount-ro, crash dumps).
- Rationale: SysRq is a physical-console attack surface (and a useful last-resort debug tool). Restrict in production, allow while diagnosing.

### 10. Kernel log and dmesg restriction

- Hardened: `dmesg_restrict=1` (with `kernel.dmesg_restrict=1` at boot). Unprivileged users cannot read the kernel ring buffer, which leaks addresses and hardware details.
- Diagnostic: `dmesg_restrict=0` during the session so diagnosis does not fight the restriction. Reverts on reboot.
- Rationale: dmesg is an info-leak channel; the diagnostic session is a trusted root session anyway.

### 11. YAMA ptrace scope

- Hardened: `kernel.yama.ptrace_scope=1` (restricted ptrace).
- Diagnostic: `kernel.yama.ptrace_scope=0` (classic ptrace) for the session, so gdb/strace attach freely.
- Rationale: per KERNEL_HARDENING.md; runtime-tunable, documented here because the two profiles are expected to differ at boot.

### 12. Lockdown mode

- Both builds: `lockdown=integrity` at boot. NOT weakened for diagnostics.
- Rationale: weakening lockdown for diagnostics would train the workflow to depend on the weaker mode. Where lockdown=integrity blocks a specific probe, the investigator documents the block and works around it (e.g. uses ftrace instead of a kprobe on a restricted path) rather than dropping to lockdown=none. If a future investigation genuinely requires it, that is a documented exception, not a config default.

## What does NOT differ

Everything else is identical: the driver set (i915 only, mt7921u, no iwlwifi, no thunderbolt, no BT), the LSM stack (AppArmor, YAMA, Landlock, lockdown), module signing enforcement, the slab/page/KASLR hardening options, the IOMMU and KVM settings, and the disabled-subsystem list. The diagnostic build is a hardened build with a flashlight, not a different kernel.

## Operational rule

The diagnostic kernel is booted from the bootloader menu for a specific investigation, then the machine returns to the hardened kernel. It is never set as the default boot entry. Its signed state means Secure Boot (once enabled) continues to trust it, so there is no temptation to disable Secure Boot "just to debug".
