# Kernel candidate evidence

Candidate release and purpose:

Evidence bundle links or hashes:

## STATIC

- [ ] Human proposal and rationale reviewed; no automatic audit promotion
- [ ] Exact source version, archive digest, signature, and signer checked
- [ ] Kconfig resolved against that authenticated source
- [ ] Requested, rejected, and collateral config deltas reviewed
- [ ] Required symbols and project policy gates pass or exceptions are explained

## BUILD

- [ ] Fresh build provenance and package/config/image binding reviewed
- [ ] Packages verified; kernel image signed by the owner

## BOOT

- [ ] Owner supervised boot of this exact release
- [ ] Secure Boot and lockdown verified on the running kernel
- [ ] 12 logical CPUs and encrypted mapper root verified
- [ ] Zero unexpected failed units or kernel errors reviewed

## HARDWARE

- [ ] Internal display and brightness
- [ ] HDMI and direct USB-C DisplayPort
- [ ] Keyboard, TrackPoint, and touchpad
- [ ] Speakers and microphone
- [ ] MT7921U Wi-Fi traffic
- [ ] USB storage read/write/eject and reinsert/read
- [ ] s2idle suspend/resume and post-resume networking/peripherals
- [ ] Real KVM guest under intended policy

## RECOVERY

- [ ] Previous custom fallback boot
- [ ] Stock distro rescue boot

## POWER

- [ ] Matched power comparison, if making a power improvement claim

CI covers static tooling only. Leave physical boxes unchecked until the owner
records evidence from the ThinkPad. A collector result is an observation, not
acceptance of a kernel candidate.
