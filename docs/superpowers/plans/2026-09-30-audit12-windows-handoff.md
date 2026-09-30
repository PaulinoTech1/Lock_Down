# Audit12 Windows Hardening Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a review-only, evidence-backed audit12 stage-0 hardening recommendation for the Linux owner.

**Architecture:** Start from the pushed audit11 resolved config and repository evidence; separate Windows/offline observations from live ThinkPad facts. Investigate bounded surfaces, recommend at most one independently testable cut set, and stop at the owner-approval gate without changing Kconfig or building a kernel.

**Tech Stack:** Git and Markdown on Windows; tracked Linux 6.18.53 Kconfig text; optional existing trusted WSL/Linux tooling for offline fixtures only.

**Spec:** [Audit12 stage-0 handoff](../../audit12/HARDENING_PHASE_SPEC.md)

## Global Constraints

- Baseline: `config/candidate-6.18.53-lockdown-t14g3-audit11.config`, SHA-256 `0076026eb1a1e405677c7fbc203888de89cfa5576cb1ac97b1953f7b7a033538`.
- Start from `origin/main` at or after `c6b07efed`; old `windows-codex` is already merged and must not be treated as new work.
- No source or config mutation, build, signing, install, reboot, firmware/sysctl/GRUB/swap change, or direct push to `main` in this stage.
- Preserve KVM, crash diagnostics, root/Secure Boot, required laptop hardware, Snap/SquashFS and recoverable stock/audit10 entries.
- Mark Windows fixtures `OFFLINE_FIXTURE`, missing runtime evidence `UNKNOWN`, and the final recommendation `REVIEW_REQUIRED`.

## Review Focus

- Dirty or diverged checkout: stop before switching branches; do not reset or overwrite user work (Task 1 check).
- Baseline digest mismatch: stop and ask which config is authoritative (Task 1 check).
- USB/IP virtual hubs or remote-token use: document as a workflow dependency, not proof that USB/IP is removable (Task 2 check).
- Watchdog or FUSE leaf with hidden selector/consumer: retain as UNKNOWN pending Linux resolution (Task 2 check).
- Offline fixture success: never promote to a hardware or boot PASS (Task 3 check).

---

### Task 1: Establish an immutable review baseline

**Files:** Read `docs/AUDIT11_OWNER_RUNBOOK.md`, `docs/audit11/RECONNAISSANCE.md`, `ISSUES.md`, `config/candidate-6.18.53-lockdown-t14g3-audit11.config`; create no files yet.

**Interfaces:** Consumes the spec and remote Git history. Produces exact baseline commit/digest and an evidence-state note for Task 2.

- [ ] **Step 1: Inspect before checkout.** In PowerShell, run `git status --short --branch`, `git fetch origin`, `git log -1 --oneline origin/main`, and `git merge-base --is-ancestor c6b07efed origin/main`. Stop if dirty, fetch fails, or ancestry fails; do not reset.
- [ ] **Step 2: Start the review branch.** From a clean checkout, run `git switch main`, `git pull --ff-only origin main`, then `git switch -c research/audit12-stage0` if that name is unused. If already on another clean research branch, document it rather than overwriting one.
- [ ] **Step 3: Verify config identity.** Run `(Get-FileHash config/candidate-6.18.53-lockdown-t14g3-audit11.config -Algorithm SHA256).Hash.ToLowerInvariant()`; require the exact digest above. Record `git rev-parse HEAD`. Stop on mismatch.
- [ ] **Step 4: Read the project boundary.** Read `lock-down-kernel/SKILL.md` and its hardware, required/forbidden-config references, the spec, runbook, reconnaissance, issue ledger, and `docs/THREAT_MODEL.md`. Record audit11's passed versus open tests without treating the Windows host as the ThinkPad.

### Task 2: Compare bounded hardening candidates

**Files:** Create `docs/audit12/STAGE0_REVIEW.md`; read the baseline config, `docs/audit11/RECONNAISSANCE.md`, and pinned Linux 6.18.53 Kconfig definitions.

**Interfaces:** Consumes Task 1's exact baseline. Produces a review memo for Task 3; no config fragment or resolved config.

- [ ] **Step 1: Inventory exact values.** Record `USBIP_CORE`, `USBIP_VHCI_HCD`, `USBIP_HOST`, watchdog leaves, `FUSE_FS`, `FUSE_DAX`, `FUSE_PASSTHROUGH`, and `FUSE_IO_URING` from the complete baseline. Use `git grep` or `Select-String` for text only; do not call text search a Kconfig resolution.
- [ ] **Step 2: Build the evidence table.** For each track in the spec, cite exact source definitions, direct and reverse dependencies when established, known ThinkPad/VM consumers, interface exposure, regression test, rollback, and confidence. Mark missing source or runtime evidence UNKNOWN. The upstream [Kconfig guide](https://docs.kernel.org/6.18/kbuild/kconfig-language.html) explains why `select`/`imply` and menu dependencies matter.
- [ ] **Step 3: Choose one bounded recommendation.** Recommend at most one independently testable cut set, or explicitly recommend no cut. State why the others are deferred. Keep core KVM, crash diagnostics, USB xHCI/storage, ThinkPad ACPI, and FUSE/AutoFS consumers unless separately evidenced.
- [ ] **Step 4: Add the owner decision gate.** Ask specifically whether remote USB import/export, remote token/recovery and guest USB workflows are required if USB/IP is preferred. List the audit11 physical, guest networking/agent/login/workload, suspend and fallback checks still needed before candidate promotion. Say `REVIEW_REQUIRED`; do not add `config/audit12-*.config`.

### Task 3: Verify and hand off the review memo

**Files:** Check `docs/audit12/STAGE0_REVIEW.md`; edit only that memo to fix review findings.

**Interfaces:** Consumes Task 2 memo. Produces a review-only branch/PR or a local commit for the owner; no candidate kernel.

- [ ] **Step 1: Check evidence labels.** Confirm every claimed PASS has Linux-host evidence in the audit11 runbook; all Windows fixtures are `OFFLINE_FIXTURE`; every unsupported absence claim is UNKNOWN.
- [ ] **Step 2: Check docs and scope.** Run `git diff --check` and the repository's `scripts/check-doc-links.sh` in an existing Linux/WSL environment if available; otherwise manually verify added relative links and state why the script did not run. Run `git diff --name-only` and require only the review memo unless a separate documentation correction is justified.
- [ ] **Step 3: Commit review work only.** Commit the memo on the research branch with a message such as `docs: propose audit12 stage0 hardening review`; push that branch or open a PR only if authenticated and permitted. Never force-push or push directly to `main`.
- [ ] **Step 4: Stop for the owner.** Report commit/PR identity, recommendation, source and runtime UNKNOWNs, required physical tests, and the exact approval question. Do not start Kconfig edits, build, signing, or deployment from a PR review or a green fixture run.
