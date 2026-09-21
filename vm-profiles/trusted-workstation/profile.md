# Profile: trusted-workstation

Daily driver VM. Assumes a non-hostile guest; isolates commodity threats
from the host while allowing the integrations that make daily use practical.
Full threat model: `../../docs/VM_THREAT_MODELS.md` (Profile 1).
Host-side hardening: `../../docs/KVM_SECURITY.md`.

Tradeoff note: every integration below (clipboard, shared folder, USB
redirect) is a deliberate hole in the guest/host boundary. They are
included because a daily driver without file transfer is unusable, but each
one lets a compromised guest reach host-side data or devices. If the guest
ever becomes suspect, stop using this profile and switch to
untrusted-analysis.

## Preconditions (LOCAL, run on the host)

- `scripts/check-iommu.sh` passes (VT-d + interrupt remapping active).
- AppArmor in enforce mode (`aa-status`), libvirt `security_driver =
  "apparmor"` in `/etc/libvirt/qemu.conf`.
- KSM off: `/sys/kernel/mm/ksm/run` reads `0`.

## virt-install example

```bash
virt-install \
  --name trusted-daily \
  --vcpus 4 \
  --memory 8192 \
  --disk size=60,bus=virtio,cache=none,discard=unmap \
  --os-variant ubuntu24.04 \
  --network network=trusted-nat,model=virtio \
  --graphics spice \
  --video virtio \
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --filesystem /srv/vm-share/trusted-daily,shared-trusted,driver.type=virtiofs \
  --noautoconsole
```

Notes:

- `--network network=trusted-nat`: a libvirt NAT network bound to the
  host `trusted` nftables zone. Stateful return traffic allowed; no
  inbound initiation from WAN. The guest is NOT bridged to the physical
  network.
- `--filesystem ... driver.type=virtiofs`: the one shared folder, scoped
  to a single staging directory (`/srv/vm-share/trusted-daily`), not the
  home directory. Files arriving from the guest are untrusted on the host.
  If virtiofs is unavailable, omit this line and transfer files via scp
  through the NAT instead (slower, narrower channel).
- Clipboard: SPICE clipboard sharing is enabled by the `spicevmc` channel
  above. Restrict to host-to-guest if the desktop supports direction
  control; otherwise accept bidirectional and treat host clipboard as
  exposed while the VM runs.
- USB redirection: not enabled at install time. Redirect specific devices
  per session from virt-manager only after checking the device is not the
  host's Wi-Fi adapter (0e8d:7961) or an input device the host needs.

## libvirt XML excerpt (equivalent hardening-relevant parts)

```xml
<domain type='kvm'>
  <name>trusted-daily</name>
  <os>
    <type arch='x86_64' machine='pc-q35-8.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'>
    <!-- host-passthrough: guest sees real CPUID, keeps microcode-backed
         mitigations visible. Cost: live migration impossible; irrelevant
         on a single laptop. -->
  </cpu>
  <devices>
    <interface type='network'>
      <source network='trusted-nat'/>
      <model type='virtio'/>
      <!-- vhost is OPTIONAL here (trusted guest): add
           <driver name='vhost'/> only with a written performance reason. -->
    </interface>
    <filesystem type='mount' accessmode='passthrough'>
      <driver type='virtiofs'/>
      <source dir='/srv/vm-share/trusted-daily'/>
      <target dir='shared-trusted'/>
    </filesystem>
    <!-- No hostdev PCI entries: no passthrough in this profile. -->
    <!-- No redirdev entries by default: USB redirect is per-session. -->
  </devices>
  <seclabel type='dynamic' model='apparmor' relabel='yes'/>
</domain>
```

## What this profile deliberately allows (and why each is risky)

- virtiofs shared folder: convenience. Risk: guest writes files the host
  user opens; guest reads anything placed in the staging dir.
- SPICE clipboard: convenience. Risk: compromised guest scrapes host
  clipboard (passwords, tokens).
- Per-session USB redirect: convenience. Risk: raw device access from the
  guest for the redirected device's session.

## Recovery

- Guest compromise: revert to the pre-use snapshot, then investigate what
  crossed the shared folder or clipboard before trusting host state.
- Host-side suspicion after guest compromise: treat as an incident; the
  profile never claimed to stop a VM escape.
