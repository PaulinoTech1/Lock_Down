# Two-domain implementation status

**Starting point:** `windows-codex` at `2a48734a20a134e1988fcccb841b448885bf694b`.
**Implementation branch:** `thinkpad-two-domain-enforcement`.
**Environment:** This checkout is on Windows at `E:\speedzone_MS\LOCK_DOWN`. It is not the target ThinkPad Linux session described in the owner instruction. WSL access was denied. No ThinkPad runtime inventory, private backup, or host policy change has occurred here.

## Repository controls built

- `scripts/verify-control-domain-isolation.py` implements a read-only state evaluator with `--expect offline|guest|maintenance`, redacted human/JSON status, and the requested exit codes. Its synthetic fixtures test unsafe routes, association, DNS, NAT, forwarding, listeners, unexpected NICs, missing evidence, guest XML summary, QEMU confinement, and maintenance exclusivity. Live collection is conservative: inaccessible process namespaces, USB identity, lease state, or system commands yield `UNKNOWN` or `FAIL`, never a successful empty inventory. Guest Internet remains `MANUAL_TEST_REQUIRED`.
- `vm-profiles/work-domain/domain.xml` is the only proposed current work-domain template. A structured validator rejects virtual NICs, host filesystems, extra host devices, agent channels, remote graphics, clipboard, file transfer, and unknown/duplicate devices. The disk path and resource sizes require host review; the XML has not been defined in libvirt.
- `vm-profiles/status.json` classifies historical profiles. Prominent banners in each legacy profile and related guidance prevent its NAT examples from reading as current daily instructions.
- `nftables/two-domain/offline.nft` is an offline/guest/transition/error guard candidate. It has `inet` and `bridge` base chains with drop policies and no global flush. It has no maintenance allowance yet. `tests/test-two-domain-nft-netns.sh` probes IPv4/IPv6 output and transaction survival in disposable Linux CI namespaces.

## Evidence levels and gaps

| Property | Current evidence | Remaining proof |
| --- | --- | --- |
| Profile prohibitions | Windows Python fixture tests and structured XML validation | Installed libvirt schema, live XML/argv and guest usability |
| Unsafe observations fail | Synthetic evaluator fixtures | Real ThinkPad inventory and negative tests |
| Host output guard | Repository template only | Linux CI namespace result, boot ordering, live nft hook/ruleset review |
| Single physical MT7921U | Documented VID:PID and example path | Current USB sysfs identity, interface binding, QEMU FD, re-enumeration |
| Ordinary-user bypass blocked | Design only | Groups, ACLs, polkit, sockets, `/dev/kvm`, raw QEMU and USB access inventory |
| QEMU/AppArmor confinement | Fixture expectations | Running PID, generated profile, seccomp, capabilities, QMP socket and denial probes |
| Maintenance transition | Design only | Expiring kernel-enforced lease, controller, rollback and host observation |

The verifier's live nft parser recognizes only a closed offline guard. Maintenance remains `UNKNOWN` until a version-tested timed allowance is implemented. The live process and USB collectors require approved domain, interface, USB path, and service-account arguments; they must be exercised on the target before trusting their version-specific parsing. A successful synthetic fixture never claims ThinkPad isolation.

## Next steps on the ThinkPad

1. Open this repository on the actual ThinkPad and confirm the branch/commit. Run the read-only Phase 0 inventory from the owner instruction, redacting SSID, BSSID, MAC/IP, USB serial, hostname, username, and secrets before any commit.
2. Make the restricted local rollback backup outside Git and verify it can be read. Preserve audit11, the previous custom kernel, and the stock Ubuntu recovery kernel.
3. Run the verifier read-only with exact owner-approved identifiers. Record every `UNKNOWN` and compare its parsers with actual installed versions. Do not interpret a nonzero result as a safe-state proof.
4. Obtain Linux CI results and review the offline guard against the live firewall backend before proposing any installation. Each live firewall, NetworkManager/USB, libvirt/permission, and AppArmor step has its own owner gate and local-console rollback.

No `lockdown-net` mutating controller, libvirt hook, maintenance opening, group/polkit change, viewer profile, storage migration, or kernel cut has been installed or claimed here. Those depend on the missing ThinkPad inventory and separate approvals.
