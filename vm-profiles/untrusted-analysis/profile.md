# Profile: untrusted-analysis

Malware-ish / suspicious software analysis. Assumes a HOSTILE guest that
may attempt escape, VM detection, and network reconnaissance. Every
convenience integration is removed. Full threat model:
`../../docs/VM_THREAT_MODELS.md` (Profile 2). Host-side hardening:
`../../docs/KVM_SECURITY.md`.

Tradeoff note: sample ingress/egress is deliberately awkward. There is no
shared folder, no clipboard, and no USB redirect, so moving a sample in or
logs out requires an explicit out-of-band step (fresh ISO attached as
cdrom, or scp over the isolated NAT to a logging host). This friction is
the control working as designed.

## Preconditions (LOCAL, run on the host; ALL must pass)

- `scripts/check-iommu.sh` passes: VT-d + interrupt remapping ACTIVE.
  If this fails, do not run this profile. UNVERIFIED IOMMU means
  UNVERIFIED containment.
- AppArmor enforce mode; libvirt `security_driver = "apparmor"`.
- KSM off: `/sys/kernel/mm/ksm/run` reads `0`. (Memory dedup side
  channels; see `KVM_SECURITY.md`.)
- Snapshot storage has free space verified before launch.
- OPTIONAL: SMT disabled (`nosmt` or `mitigations=auto,nosmt`) while
  hostile VMs run, to narrow cross-thread speculation channels. Cost:
  loses 2 threads on the P-cores; re-enable after the session. See
  `../../docs/CPU_SECURITY.md`.

## Isolated network definition

Define once per host (virsh net-define):

```xml
<network>
  <name>untrusted-isolated</name>
  <forward mode='nat'/>
  <ip address='192.168.200.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.200.10' end='192.168.200.50'/>
    </dhcp>
  </ip>
  <!-- No DNS forwarder defined here: the guest gets no name resolution
       unless the analyst explicitly adds a logging resolver. Samples that
       beacon to hardcoded IPs still work at L3; that traffic is visible
       in the host nftables log for the zone. -->
</network>
```

nftables zone `untrusted` (host side): NAT out, no forwarding to the host
LAN, no forwarding to other zones, no inbound initiation. Log new outbound
connections for analysis review.

## virt-install example

```bash
virt-install \
  --name untrusted-001 \
  --vcpus 2 \
  --memory 4096 \
  --disk /var/lib/libvirt/images/untrusted-001.qcow2,size=40,bus=virtio,cache=none \
  --os-variant ubuntu24.04 \
  --network network=untrusted-isolated,model=virtio \
  --graphics spice \
  --video virtio \
  --noautoconsole \
  --noreboot
```

Deliberate omissions (each is a control, not an oversight):

- No `--filesystem`: no 9p, no virtiofs, no host mounts of any kind.
- No `--redirdev`: no USB redirection at all. The external Wi-Fi adapter
  (0e8d:7961) is the host's only network path and must never be handed to
  a hostile guest.
- No `--hostdev`: no PCI passthrough.
- No SPICE clipboard channel: no `spicevmc` channel defined, so no
  clipboard sharing path exists to enable by accident.

## libvirt XML excerpt (hardening-relevant parts)

```xml
<domain type='kvm'>
  <name>untrusted-001</name>
  <os>
    <type arch='x86_64' machine='pc-q35-8.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <devices>
    <interface type='network'>
      <source network='untrusted-isolated'/>
      <model type='virtio'/>
      <!-- No vhost driver: virtio processed in QEMU userspace under sVirt.
           Slower; keeps descriptor parsing out of the host kernel. -->
    </interface>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/untrusted-001.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <!-- No filesystem, no redirdev, no hostdev, no spicevmc channel. -->
    <graphics type='spice'>
      <clipboard copypaste='no'/>
    </graphics>
  </devices>
  <!-- Pinned sVirt label: this QEMU process is confined to exactly its
       own resources. Dynamic labeling is acceptable, but pinning makes
       the confinement auditable per analysis run. -->
  <seclabel type='static' model='apparmor' relabel='yes'>
    <label>libvirt-untrusted-001</label>
    <imagelabel>libvirt-untrusted-001</imagelabel>
  </seclabel>
</domain>
```

## Operational rules

- One disk image per analysis target; create fresh per run. Never reuse an
  image across targets without documenting why.
- Snapshot before executing the sample. Verify the snapshot exists before
  proceeding.
- Sample ingress: attach a freshly written ISO as cdrom, or scp from an
  analysis staging host over the isolated NAT. Document which method was
  used per run.
- After the run: shut down, review nftables zone logs, then revert or
  delete the image. Do not keep hostile images lying around unlabeled.

## What this profile does NOT protect against

- VM escape (KVM/QEMU bug), microarchitectural side channels shared with
  the host, VM detection/evasion by the sample, firmware-level persistence.
  See `VM_THREAT_MODELS.md`.

## Recovery

- Suspected escape or host-side anomaly during a run: stop the VM, preserve
  the disk image and host logs, treat as an incident. The profile's job was
  containment; investigate from the host side, not from inside the guest.
