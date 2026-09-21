# Kernel Hardening Evaluation

Target: Lenovo ThinkPad T14 Gen 3 Intel (21AJ), i5-1245U Alder Lake-U, i915 only, NVMe, USB Wi-Fi (mt7921u), TPM 2.0, KVM/libvirt use case, Ubuntu 24.04 userspace, KDE Plasma Wayland.

Legend: VERIFIED (confirmed against this hardware or unambiguous), RECOMMENDED (adopt), OPTIONAL (judgment call), EXPERIMENTAL (needs measurement), UNVERIFIED (cannot confirm yet).

Each option is evaluated on: purpose, security benefit, compatibility risk, estimated performance cost, decision, reason. Decisions are justified against Alder Lake-U and this single-user workstation threat model (local privilege escalation, malicious peripherals on USB, hostile VMs under KVM, evil-maid via unsigned boot until Secure Boot is enabled). They are not copied from a generic checklist.

## Compiler and memory-safety hardening

### STACKPROTECTOR_STRONG
- Purpose: insert stack canaries in functions with character arrays or address-taken locals.
- Security benefit: detects stack buffer overflows at runtime before return-address corruption is exploited. Standard, high-value mitigation.
- Compatibility risk: none known on x86_64.
- Performance cost: negligible (<1% typical).
- Decision: ENABLE.
- Reason: baseline exploit mitigation with no downside on this platform.

### FORTIFY_SOURCE
- Purpose: compile-time and runtime bounds checking on common libc-like functions (memcpy, strcpy, sprintf) inside the kernel.
- Security benefit: turns many linear overflows into caught faults instead of silent corruption.
- Compatibility risk: none on mainline 6.18 with a modern gcc; occasional false positives in out-of-tree code, which this project does not carry.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: free detection of a common bug class; required by any serious hardened build.

### HARDENED_USERCOPY
- Purpose: validate copy_to_user/copy_from_user bounds against the actual slab object size.
- Security benefit: catches heap over/under-reads and writes at the usercopy boundary, a historically rich source of kernel CVEs.
- Compatibility risk: low on mainline; some drivers historically tripped it, but the enabled set here (i915, nvme, mt7921u, SOF) is mainline-clean.
- Performance cost: negligible (length checks on an already-expensive path).
- Decision: ENABLE.
- Reason: high signal, near-zero cost, matches the reduced-driver threat model where each remaining driver is high-value.

### INIT_ON_ALLOC_DEFAULT_ON
- Purpose: zero heap memory at allocation time by default.
- Security benefit: kills uninitialized-heap info leaks and use-of-uninitialized-data bugs, a large fraction of info-disclosure CVEs.
- Compatibility risk: low; some performance-sensitive paths opt out explicitly upstream.
- Performance cost: measurable, roughly low single-digit percent on allocation-heavy workloads (builds, VM churn). On a 10C/12T Alder Lake-U workstation this is acceptable.
- Decision: ENABLE.
- Reason: the info-leak protection is worth the small throughput cost on an interactive workstation.

### INIT_ON_FREE_DEFAULT_ON
- Purpose: zero heap memory at free time by default.
- Security benefit: prevents use-after-free data disclosure and makes freed-memory reuse attacks harder.
- Compatibility risk: low.
- Performance cost: MEASURABLE, higher than INIT_ON_ALLOC. Free-path zeroing hits slab-intensive workloads (network, block I/O, VM exits). Expect low-to-mid single-digit percent on affected paths; interactive latency impact is small but real.
- Decision: ENABLE, with the cost acknowledged and measured on this machine before finalizing.
- Reason: defense in depth against UAF info leaks complements INIT_ON_ALLOC. The cost is real and must be measured (OPTIONAL to disable if benchmarks show unacceptable interactive latency), but the default is on.

### SLAB_FREELIST_HARDENED
- Purpose: store freelist pointers obfuscated and add canaries to slab freelists.
- Security benefit: raises the bar on freelist corruption / fake-object attacks.
- Compatibility risk: none.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: standard hardening, no tradeoff.

### SLAB_FREELIST_RANDOM
- Purpose: randomize slab freelist order to make heap layout less predictable.
- Security benefit: weakens heap-spray reliability.
- Compatibility risk: none.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: pairs with SHUFFLE_PAGE_ALLOCATOR; no downside.

### SHUFFLE_PAGE_ALLOCATOR
- Purpose: randomize the page allocator freelist.
- Security benefit: reduces determinism of physical page reuse, blunting heap grooming.
- Compatibility risk: none on x86_64.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: cheap entropy against heap grooming; no measurable cost.

### VMAP_STACK
- Purpose: allocate kernel stacks in virtually mapped memory with a guard page.
- Security benefit: stack overflows fault on the guard page instead of corrupting adjacent memory.
- Compatibility risk: none on x86_64 (default in modern kernels).
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: should already be default; keep it explicit.

## Address-space and KASLR options

### RANDOMIZE_BASE
- Purpose: randomize the kernel image base address at boot (KASLR).
- Security benefit: defeats hardcoded kernel-address exploitation.
- Compatibility risk: none on UEFI boot with this hardware.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: baseline ASLR for the kernel; required.

### RANDOMIZE_MEMORY
- Purpose: randomize physical memory, vmalloc, and vmemmap regions on top of RANDOMIZE_BASE.
- Security benefit: extends KASLR coverage so fewer kernel addresses are predictable.
- Compatibility risk: low; some hibernation setups care, but this machine uses s2idle only (no hibernation planned with LUKS2+TPM2+PIN).
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: completes KASLR; no hibernation conflict on this suspend policy.

### RANDOMIZE_KSTACK_OFFSET
- Purpose: randomize the kernel stack offset per syscall.
- Security benefit: blunts stack-address info leaks used to aim ROP chains.
- Compatibility risk: none known on x86_64.
- Performance cost: small (per-syscall reseeding cost is low).
- Decision: ENABLE.
- Reason: cheap additional entropy on the syscall path.

## Code-integrity options

### STRICT_KERNEL_RWX
- Purpose: enforce W^X on kernel text/rodata (write-xor-execute).
- Security benefit: prevents runtime patching of kernel code and execution of writable data.
- Compatibility risk: none on x86_64 mainline.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: foundational code-integrity guarantee.

### STRICT_MODULE_RWX
- Purpose: same W^X enforcement for loaded modules.
- Security benefit: modules cannot be both writable and executable at runtime.
- Compatibility risk: none with in-tree modules.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: extends STRICT_KERNEL_RWX to the module path this build relies on.

### MODULE_SIG and MODULE_SIG_FORCE
- Purpose: sign modules at build; with _FORCE, refuse to load unsigned modules.
- Security benefit: blocks loading of attacker-supplied or tampered modules, which matters on a machine where the boot chain is currently unsigned (Secure Boot disabled today) and where USB peripherals are the network path.
- Compatibility risk: all modules must be signed at build time; out-of-tree modules would need the key. This project builds all needed modules in-tree (mt7921u, USB net dongles), so the risk is contained. DKMS-style out-of-tree modules are not part of this design.
- Performance cost: negligible at load; build-time only.
- Decision: ENABLE both now, ready for Secure Boot enablement (shim+MOK) later. The signing key is generated at build time and kept local; enrollment into MOK happens at the Secure Boot step, not before.
- Reason: MODULE_SIG_FORCE closes the unsigned-module hole that otherwise undermines lockdown=integrity. Enabling it now means the Secure Boot bringup does not require a config change later.

### SECURITY (LSM framework)
- Purpose: enable the Linux Security Module stacking framework.
- Security benefit: prerequisite for AppArmor, YAMA, Landlock, lockdown.
- Compatibility risk: none.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: non-negotiable foundation for everything below.

### SECURITY_APPARMOR
- Purpose: AppArmor mandatory access control.
- Security benefit: per-program confinement; the userspace plan already includes AppArmor plus sVirt confinement for libvirt guests, so the kernel side must be present.
- Compatibility risk: none; Ubuntu userspace expects it.
- Performance cost: negligible to small (path-based checks on exec/open).
- Decision: ENABLE.
- Reason: the userspace security stack is built on it.

### SECURITY_YAMA
- Purpose: restrict ptrace scope (classic YAMA levels).
- Security benefit: limits cross-process memory inspection/injection to same-UID or explicit opt-in, raising the bar for local privesc and credential theft from user processes.
- Compatibility risk: debugging tools need the right scope setting; the diagnostic build keeps full tracing anyway, and scope is a runtime sysctl (kernel.yama.ptrace_scope), so this is reversible per boot.
- Performance cost: negligible.
- Decision: ENABLE, default scope 1 (restricted ptrace) on the hardened build; scope 0 on the diagnostic build.
- Reason: cheap anti-ptrace-abuse control; runtime-tunable so debuggability is preserved where wanted.

### SECURITY_LANDLOCK
- Purpose: unprivileged sandboxing LSM (used by systemd, browsers, Flatpak-style sandboxes).
- Security benefit: lets user processes self-confine filesystem and network access without privilege, which matters on a workstation running a browser and VMs.
- Compatibility risk: none; additive.
- Performance cost: negligible.
- Decision: ENABLE.
- Reason: modern sandboxing primitive; Ubuntu/systemd userspace can consume it.

### SECURITY_LOCKDOWN_LSM (lockdown=integrity)
- Purpose: lockdown LSM restricting kernel features that allow raw access (kexec of unsigned kernels, /dev/mem, module loading of unsigned code under _FORCE, perf access to kernel addresses, debugfs restrictions).
- Security benefit: closes the "root can just read kernel memory" paths, which is the correct posture once Secure Boot is enabled and module signing is enforced. Set to `integrity` (not `confidentiality`), so perf and tracing still function for the owner while raw kernel modification is blocked.
- Compatibility risk: `integrity` mode can block legitimate debugging (kprobes on some paths, unsigned kexec). The diagnostic config documents exactly which lockdown interactions differ (see HARDENED_VS_DIAGNOSTIC.md). Until Secure Boot is enabled, lockdown is advisory rather than anchored, which is accepted and documented.
- Performance cost: negligible.
- Decision: ENABLE, boot with `lockdown=integrity`.
- Reason: `integrity` is the right middle ground for an owner-administered workstation: it blocks kernel tampering paths while keeping the machine debuggable. Full `confidentiality` would fight the diagnostic workflow.

## Speculative-execution mitigations (arch-specific)

### PAGE_TABLE_ISOLATION
- Purpose: separate user/kernel page tables (Meltdown mitigation).
- Security benefit: on affected CPUs, prevents user-space reading of kernel memory via speculative side channel.
- Compatibility risk: none.
- Performance cost: measurable on syscall-heavy workloads on older CPUs; on Alder Lake (not Meltdown-vulnerable in the classic sense) the kernel enables it only where needed. Cost on this CPU: negligible.
- Decision: ENABLE (let the kernel decide per-CPU applicability).
- Reason: keep the option available; the kernel applies it only to vulnerable silicon.

### IBRS / eIBRS handling
- Purpose: Indirect Branch Restricted Speculation; eIBRS is the always-on hardware variant.
- Security benefit: mitigates Spectre v2 (branch target injection).
- Compatibility risk: none; Alder Lake supports eIBRS in hardware, and the kernel uses it automatically when present. Retpoline remains the fallback for paths where eIBRS does not cover.
- Performance cost: eIBRS has lower overhead than software IBRS; retpoline costs are already baked into the distro baseline. No additional config cost beyond defaults.
- Decision: defaults (kernel auto-selects eIBRS on Alder Lake). Do NOT force `spectre_v2=ibrs` (software IBRS is slower and unnecessary here) and do NOT disable mitigations.
- Reason: Alder Lake has the hardware fix; the kernel's default selection is already the optimal one. Forcing anything is strictly worse.

### Retbleed handling
- Purpose: mitigation for RETBleed (Spectre-like return-stack speculation) on affected AMD/Intel CPUs.
- Security benefit: relevant to older Intel (Skylake-era) and AMD Zen; Alder Lake is not in the affected set for the Intel retbleed variant in a way that changes the default.
- Compatibility risk: none.
- Performance cost: none beyond defaults on this CPU.
- Decision: defaults (no explicit retbleed= parameter; kernel applies what the CPU needs, which on Alder Lake-U is nothing extra).
- Reason: no Alder Lake-U-specific retbleed exposure; explicit knobs would only risk misconfiguration. Verify at runtime via /sys/devices/system/cpu/vulnerabilities/retbleed.

General rule for speculative-execution options on this build: take the kernel defaults, do not disable mitigations, and verify the live state under /sys/devices/system/cpu/vulnerabilities/ after first boot. Disabling mitigations for performance is explicitly out of scope for this threat model.

## Device-memory and raw-access restrictions

### STRICT_DEVMEM
- Purpose: restrict /dev/mem to the first 1 MB and other architecturally required regions.
- Security benefit: blocks trivial physical-memory reads through /dev/mem.
- Compatibility risk: none on modern userspace (Xorg needed it decades ago; Wayland/KDE does not).
- Performance cost: none.
- Decision: ENABLE.
- Reason: /dev/mem has no legitimate user on this machine.

### IO_STRICT_DEVMEM
- Purpose: extend the same restriction to /dev/port and related I/O access.
- Security benefit: closes the /dev/port side door to raw hardware access.
- Compatibility risk: none expected; legacy tools (dosemu-style) are not in scope.
- Performance cost: none.
- Decision: ENABLE.
- Reason: completes STRICT_DEVMEM; no legitimate consumer on this workstation.

## What is deliberately NOT enabled in the hardened build

- KASAN / KCSAN / UBSAN-instrumented production: excluded from the hardened build (prohibitive performance and memory cost; they are debug tools, not deployment mitigations). The diagnostic build may carry UBSAN only if a specific investigation needs it; KASAN/KCSAN stay out of both shipped kernels. Rationale is in HARDENED_VS_DIAGNOSTIC.md.
- IMA/EVM: evaluated, not enabled. Without a measured boot chain and a file-signing workflow, IMA appraisal adds boot complexity and failure modes for little gain on a single-user workstation where AppArmor + lockdown + module signing already cover the high-value paths. Revisit after Secure Boot is enabled and the boot chain is measured. Classification: OPTIONAL, deferred.
- Full lockdown=confidentiality: rejected in favor of integrity (see above); confidentiality would break the diagnostic workflow and perf-based tuning with no meaningful gain for this threat model.
