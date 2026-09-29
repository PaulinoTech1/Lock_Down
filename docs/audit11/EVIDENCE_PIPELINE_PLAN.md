# Audit11 evidence pipeline implementation plan

1. Specify versioned JSON reports, exact CLI contracts, trust boundaries,
   output privacy, and exit meanings in the design and schema files. Commit.
2. Add failing pure classification fixtures for accepted, rejected, collateral,
   required-symbol regression, baseline drift, wrong source version, and input
   preservation. Implement the Kconfig analyzer and direct-clause source index.
   Run its fixtures and existing policy gates, inspect the diff, commit.
3. Add offline collector fixtures for healthy evidence, wrong release, disabled
   Secure Boot, lockdown none, two CPUs, missing KVM/IOMMU/Wi-Fi/s2idle,
   failed units, graphics firmware errors, and unreadable inputs. Implement
   bounded read-only collection and generated manual checklist. Run fixtures,
   inspect the bundle for identifiers, commit.
4. Reconcile ISSUES.md against audit10 owner evidence and current tooling,
   preserving historical findings. Add a kernel-candidate PR template and
   developer instructions. Commit by concern.
5. Add only static/offline CI gates. Run available Windows fixtures and all
   current-candidate gates. Let GitHub Actions establish Linux results. Review
   the final diff, frozen-file scope, branch and status; publish to the
   existing `windows-codex` collaboration branch.

No candidate config, owner signing, installation, boot, suspend, firmware,
TPM, GRUB, recovery setting, or physical ThinkPad action is in this plan.
