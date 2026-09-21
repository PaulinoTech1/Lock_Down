# USB Security (USBGuard)

Purpose: control which USB devices the kernel authorizes, so a malicious or unexpected device (BadUSB-style HID, rogue network gadget, storage with autorun payloads) cannot simply plug in and act.

Status: RECOMMENDED, with the hard constraint below. Confidence: High on the mechanism; Medium on any specific ruleset until it is proven on the machine.

## Hard constraint

The MediaTek MT7921U USB Wi-Fi adapter (VID:PID 0e8d:7961, attached to PCH xHCI bus 4 port 1) is the ONLY network path on this workstation. Any USB authorization policy must whitelist this device BEFORE any default-deny rule can be enforced. A default-deny policy applied without a proven whitelist kills networking at boot and leaves no remote recovery path.

Additional facts that shape the rules:

- USB Wi-Fi is on bus 4 port 1. Rules qualify the adapter by VID:PID AND bus/port path, not VID:PID alone.
- VID/PID alone is NOT strong identity. USB descriptors are trivially spoofable; a hostile device can claim to be 0e8d:7961. The port-path qualifier raises the bar (the attacker needs physical access to that port) but does not make it cryptographic. Document this honestly: the rule set is a speed bump against casual attacks and misplugged devices, not a defense against a targeted attacker with physical access.

## Rule design

Order in usbguard/rules.conf:

1. Allow the USB controller and root hubs first. Without these, nothing downstream enumerates at all.
2. Allow the MT7921U on its port path (bus 4 port 1), keyed by VID:PID plus `via-port`. Comment in the file explains how to tighten with the device serial (`serial "..."`), which should be filled in at deployment from `usbguard list-devices`.
3. Allow the YubiKey by VID:PID with a serial-aware rule. Fill in the serial at deployment; the placeholder is marked in the rules file.
4. Reject everything else with a message (`reject` with `with-message`), so blocked devices get feedback instead of a silent hang.
5. No automation in this project flips the USB authorization default. The rules file is a starting point to be tested by hand.

## Boot-order warning

USBGuard applies policy at enumeration. If the daemon or its rules fail at boot, the Wi-Fi adapter may stay unauthorized and the machine boots with no network. Test the ruleset with the daemon in a non-enforcing mode first, confirm the adapter is authorized, and only then consider enforcement. Keep a known-good rules backup.

## Deployment procedure

1. Install USBGuard and generate the current device list: `usbguard generate-policy` while ONLY trusted devices are attached. Compare its output against usbguard/rules.conf by hand.
2. Fill in the YubiKey serial and the MT7921U serial in the local copy of the rules file only. Serials are unique hardware identifiers: tighten the rules on the machine, but never commit them to the repository (see docs/SECRETS.md).
3. Load the rules without enforcement, verify `usbguard list-devices` shows the adapter and key as allowed.
4. Reboot and verify networking comes up. Only then treat the policy as proven.
5. Document the proven ruleset state (date, daemon version) in this file's deployment notes.

## Limitation

- Spoofable descriptors (above). Physical port access defeats port-path qualifiers.
- USBGuard authorizes at the USB level; it does not inspect what a permitted device does afterward (a permitted HID is still a keyboard).
- The policy must be re-verified after kernel or USBGuard upgrades and after any hardware change (dock, new key).

## Recovery

- Boot with the USBGuard rules reverted: keep a backup of the last-known-good rules.conf. The daemon reads its config from disk, so a Live USB or the rescue kernel can restore the backup.
- If the Wi-Fi adapter is blocked at boot, there is no network-based recovery; physical access and a console are required. This is why the whitelist is proven before enforcement.

## Cost

One-time setup and testing effort. Ongoing: each new legitimate USB device needs a rule entry before it works, which is friction by design.
