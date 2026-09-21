# AppArmor

Purpose: mandatory access control that confines programs to the files and capabilities they actually need, so a compromised process cannot freely read the home directory, raw devices, or the network.

Status: RECOMMENDED as the primary MAC. Confidence: High (Ubuntu integrates AppArmor deeply; the kernel skill confirms the substrate).

## Primary MAC: AppArmor

- Ubuntu ships AppArmor enabled with profiles for many system services. This project treats AppArmor as the primary MAC and does not add a second full MAC system.
- Landlock is retained for applications that use it themselves (it is unprivileged and per-process); it complements AppArmor rather than replacing it.
- Rule: no filler profiles. Every profile in this project is short, understandable, and testable. A profile nobody can read is a profile nobody can maintain, and an unmaintained profile becomes a denial-of-service on its own program.

## Confinement scope

- libvirt/QEMU guests: Ubuntu's libvirt ships with sVirt AppArmor confinement (per-guest profiles under /etc/apparmor.d/libvirt). Keep it enabled and in enforce mode. Verify with `aa-status`.
- Selected exposed services: any network listener this workstation runs (see docs/FIREWALL.md and docs/SSH.md) gets a reviewed profile before it is enabled.
- Project utilities: the project's own scripts (auditors, checkers) get minimal profiles so they run with least privilege. See apparmor/ for examples.
- Everything else: default Ubuntu profiles stay as shipped. Do not invent profiles for programs you have not profiled.

## How to test a profile

1. Load in complain mode first: `aa-complain <profile>`. The program runs normally; denials are logged, not enforced.
2. Exercise the program through its real workflows (not just startup).
3. Review denials: `journalctl -t audit` or `dmesg | grep apparmor`, or `aa-logprof` interactively. Every granted permission must map to an observed, legitimate need.
4. Switch to enforce: `aa-enforce <profile>`. Re-run the workflows. Any new denial is a bug in the profile or a behavior change to investigate.
5. Record what was tested and when, next to the profile.

## How to recover from a broken profile

1. Drop to complain mode: `aa-complain <profile>`. This restores function immediately while keeping the logging.
2. If the system is badly wedged, boot the rescue kernel (distro kernel, unaffected by project profiles) or use a Live USB, then fix or remove the profile from outside.
3. Never "fix" a broken profile by granting broad permissions to make the errors stop. Find the actual needed access and grant exactly that.

## Yama scope

- Yama (`kernel.yama.ptrace_scope`) restricts ptrace to parent/child by default on Ubuntu (scope 1). Keep scope 1. Raising it weakens debugging isolation; lowering to 2 or 3 breaks legitimate debugging workflows without a clear threat model demanding it.
- Verify: `sysctl kernel.yama.ptrace_scope`.

## Landlock notes

- Landlock is available to unprivileged processes; some sandboxed apps (browsers, for example) use it internally. Nothing to configure here; just do not disable it in the kernel.
- Landlock rules stack with AppArmor: a process confined by both must satisfy both.

## Limitation

- AppArmor is path-based; a program that can write to a path it legitimately uses can still abuse that path. It is containment, not a correctness proof.
- Profiles must be maintained across package upgrades that change program behavior; an upgrade can introduce new legitimate accesses that a strict profile then denies.
- sVirt confinement depends on libvirt actually applying the per-guest profiles; verify after libvirt upgrades.

## Cost

Profile maintenance per upgrade cycle. The discipline of complain-first testing avoids the classic failure mode of shipping an enforce profile that breaks the program it was meant to protect.
